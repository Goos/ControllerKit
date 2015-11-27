//
//  Service.swift
//  ControllerKit
//
//  Created by Robin Goos on 25/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import GameController
import Act

@objc public protocol ControllerBrowserDelegate : class {
    func controllerBrowser(browser: ControllerBrowser, controllerConnected controller: Controller, type: ControllerType)
    func controllerBrowser(browser: ControllerBrowser, controllerDisconnected controller: Controller)
    func controllerBrowser(browser: ControllerBrowser, encounteredError error: NSError)
}

@objc public enum ControllerType : Int {
    case MFi
    case HID
    case Remote
}

final class RemotePeer {
    var controllers: [UInt16:Controller] = [:]
    let connectChannel: ReadChannel<ControllerConnectedMessage>
    let nameChannel: ReadChannel<RemoteMessage<ControllerNameMessage>>
    let gamepadChannel: ReadChannel<RemoteMessage<GamepadMessage>>
    
    init(connectChannel: ReadChannel<ControllerConnectedMessage>, nameChannel: ReadChannel<RemoteMessage<ControllerNameMessage>>, gamepadChannel: ReadChannel<RemoteMessage<GamepadMessage>>) {
        self.connectChannel = connectChannel
        self.nameChannel = nameChannel
        self.gamepadChannel = gamepadChannel
        
        nameChannel.receive { message in
            if let controller = self.controllers[message.controllerIndex] {
                controller.name = message.message.name
            }
        }
        
        gamepadChannel.receive { message in
            if let controller = self.controllers[message.controllerIndex] {
                controller.inputHandler.send(message.message)
            }
        }
    }
}

let kLocalDomain = "local."
let kControllerConnectedMessageLength: UInt = 10

/*! 
    @class Server
    
    @abstract
    Server is represents an entity to which Clients and Controllers can connect.
*/
public final class ControllerBrowser : NSObject, HIDManagerDelegate, NSNetServiceDelegate, GCDAsyncSocketDelegate {
    public let name: String
    public let serviceIdentifier: String
    public weak var delegate: ControllerBrowserDelegate?
    
    public var controllers: [Controller] {
        return [Array(mfiControllers.values), remotePeers.flatMap { $1.controllers.values }, Array(hidControllers)].flatMap { $0 }
    }
    private var mfiControllers: [GCControllerPlayerIndex:Controller] = [:]
    private var hidControllers: Set<Controller> = []
    
    private let controllerTypes: Set<ControllerType>
    
    private var netService: NSNetService?
    private let discoverySocket: GCDAsyncSocket
    private let inputConnection: UDPConnection
    private var remotePeers: [String:RemotePeer] = [:]
    
    private var connections: Set<TCPConnection> = []
    
    private let hidManager: HIDControllerManager
    
    private let networkQueue = dispatch_queue_create("com.controllerkit.network_queue", DISPATCH_QUEUE_CONCURRENT)
    private let inputQueue = dispatch_queue_create("com.controllerkit.input_queue", DISPATCH_QUEUE_SERIAL)
    private let queueable: DispatchQueueable
    
    public convenience init(name: String) {
        self.init(name: name, controllerTypes: [.Remote])
    }
    
    public init(name: String, serviceIdentifier: String = "controllerkit", controllerTypes: Set<ControllerType>) {
        self.name = name
        self.serviceIdentifier = serviceIdentifier
        self.controllerTypes = controllerTypes
        
        queueable = inputQueue.queueable()
        
        discoverySocket = GCDAsyncSocket(socketQueue: networkQueue)
        inputConnection = UDPConnection(socketQueue: networkQueue, delegateQueue: inputQueue)
        
        hidManager = HIDControllerManager()
        
        super.init()
        
        discoverySocket.synchronouslySetDelegate(self, delegateQueue: inputQueue)
        
        #if os(OSX)
        hidManager.delegate = self
        #endif
    }
    
    public func start() {
        if controllerTypes.contains(.Remote) {
            do {
                try discoverySocket.acceptOnPort(0)
                let port = discoverySocket.localPort
                
                inputConnection.listen(0, success: {
                    let txtRecord = ServerTXTRecord(inputPort: self.inputConnection.port)
                    let serviceType = "_\(self.serviceIdentifier)._tcp"
                    self.netService = NSNetService(domain: kLocalDomain, type: serviceType, name: self.name, port: Int32(port))
                    self.netService?.setTXTRecordData(txtRecord.marshal())
                    self.netService?.delegate = self
                    self.netService?.includesPeerToPeer = false
                    self.netService?.publish()
                }, error: { err in
                    self.delegate?.controllerBrowser(self, encounteredError: err)
                })
            } catch let error as NSError {
                self.delegate?.controllerBrowser(self, encounteredError: error)
            }
        }
        if controllerTypes.contains(.MFi) {
            GCController.startWirelessControllerDiscoveryWithCompletionHandler(nil)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "controllerDidConnect:", name: GCControllerDidConnectNotification, object: nil)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "controllerDidDisconnect:", name: GCControllerDidDisconnectNotification, object: nil)
        }
        
        #if os(OSX)
        if controllerTypes.contains(.HID) {
            hidManager.start()
        }
        #endif
    }
    
    public func stop() {
        if controllerTypes.contains(.Remote) {
            netService?.stop()
            for conn in connections {
                conn.disconnect()
            }
        }
        if controllerTypes.contains(.MFi) {
            GCController.stopWirelessControllerDiscovery()
            NSNotificationCenter.defaultCenter().removeObserver(self, name: GCControllerDidConnectNotification, object: nil)
        }
        
        #if os(OSX)
        hidManager.stop()
        #endif
    }
    
    func controllerForNativeController(controller: GCController) -> Controller {
        var layout: GamepadLayout
        if controller.extendedGamepad != nil {
            layout = .Extended
        } else if controller.gamepad != nil {
            layout = .Regular
        } else {
            layout = .Micro
        }
        let gamepad = GamepadState(layout: layout)
        let inputHandler = ObservableActor(initialState: gamepad, transformers: [], reducer: GamepadStateReducer, processingQueue: queueable)
        pipe(controller, inputHandler)
        return Controller(inputHandler: inputHandler)
    }
    
    // MARK: GCController discovery
    func controllerDidConnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController {
            if let existing = mfiControllers[nativeController.playerIndex] {
                existing.status = .Connected
            } else {
                let controller = controllerForNativeController(nativeController)
                controller.index = UInt16(controllers.count)
                mfiControllers[nativeController.playerIndex] = controller
                
                delegate?.controllerBrowser(self, controllerConnected: controller, type: .MFi)
            }
        }
    }
    
    func controllerDidDisconnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController, controller = mfiControllers[nativeController.playerIndex] {
            controller.status = .Disconnected
            
            NSTimer.setTimeout(12) { [weak self] in
                if controller.status == .Disconnected {
                    self?.delegate?.controllerBrowser(self!, controllerDisconnected: controller)
                    self?.mfiControllers.removeValueForKey(nativeController.playerIndex)
                }
            }
        }
    }
    
    // MARK: HIDManagerDelegate
    func manager(manager: HIDControllerManager, controllerConnected controller: Controller) {
        controller.index = UInt16(controllers.count)
        hidControllers.insert(controller)
        self.delegate?.controllerBrowser(self, controllerConnected: controller, type: .HID)
    }
    
    func manager(manager: HIDControllerManager, controllerDisconnected controller: Controller) {
        hidControllers.remove(controller)
        self.delegate?.controllerBrowser(self, controllerDisconnected: controller)
    }
    
    func manager(manager: HIDControllerManager, encounteredError error: NSError) {
        self.delegate?.controllerBrowser(self, encounteredError: error)
    }
    
    // MARK: NSNetServiceDelegate
    public func netServiceDidPublish(sender: NSNetService) {
        
    }
    
    public func netService(sender: NSNetService, didNotPublish errorDict: [String : NSNumber]) {
        if let code = errorDict[NSNetServicesErrorCode] as? Int {
            let error = NSError(domain: "com.controllerkit.netservice", code: code, userInfo: errorDict)
            self.delegate?.controllerBrowser(self, encounteredError: error)
        }
    }
    
    public func netServiceDidStop(sender: NSNetService) {

    }
    
    // MARK: GCDAsyncSocketDelegate
    public func socket(sock: GCDAsyncSocket!, didAcceptNewSocket newSocket: GCDAsyncSocket!) {
        let tcpConnection = TCPConnection(socket: newSocket, delegateQueue: inputQueue)
        tcpConnection.send(ControllerNameMessage(name: "asdy").marshal())
        connections.insert(tcpConnection)
        
        let host = newSocket.connectedHost
        
        var peer: RemotePeer
        if let p = remotePeers[host] {
            peer = p
        } else if let cc = tcpConnection.registerReadChannel(1, host: host, type: ControllerConnectedMessage.self),
            nc = tcpConnection.registerReadChannel(2, type: RemoteMessage<ControllerNameMessage>.self),
            gc = inputConnection.registerReadChannel(3, host: host, type: RemoteMessage<GamepadMessage>.self) {
            peer = RemotePeer(connectChannel: cc, nameChannel: nc, gamepadChannel: gc)
            cc.onReceive = { message in
                if let controller = peer.controllers[message.index] {
                    controller.status = .Connected
                } else {
                    let inputHandler = ControllerInputHandler(GamepadState(layout: .Regular), processingQueue: self.inputQueue.queueable())
                    let controller = Controller(inputHandler: inputHandler)
                    controller.index = UInt16(self.controllers.count)
                    peer.controllers[message.index] = controller
                    
                    self.delegate?.controllerBrowser(self, controllerConnected: controller, type: .Remote)
                }
                tcpConnection.socket.readDataToLength(kControllerConnectedMessageLength, withTimeout: -1, tag: 0)
                
            }
            remotePeers[host] = peer
        } else {
            return
        }
        
        tcpConnection.onDisconnect = {
            for (_, controller) in peer.controllers {
                controller.status = .Disconnected
            }
            
            // Removing the controllers after a timeout.
            NSTimer.setTimeout(12) {
                for (index, controller) in peer.controllers {
                    if controller.status == .Disconnected {
                        self.delegate?.controllerBrowser(self, controllerDisconnected: controller)
                        peer.controllers.removeValueForKey(index)
                    }
                }
                
                if peer.controllers.count == 0 {
                    self.inputConnection.deregisterReadChannel(peer.gamepadChannel)
                    self.remotePeers.removeValueForKey(host)
                }
            }
        }
        
        tcpConnection.onError = { err in
            self.delegate?.controllerBrowser(self, encounteredError: err)
        }
        
        tcpConnection.socket.readDataToLength(kControllerConnectedMessageLength, withTimeout: -1, tag: 0)
    }
    
    public func newSocketQueueForConnectionFromAddress(address: NSData!, onSocket sock: GCDAsyncSocket!) -> dispatch_queue_t! {
        return networkQueue
    }
}

public struct ServerTXTRecord : Marshallable {
    let kInputPortKey = "INPUT_PORT"
    let inputPort: UInt16
    
    init(inputPort: UInt16) {
        self.inputPort = inputPort
    }
    
    init?(data: NSData) {
        let dictionary = NSNetService.dictionaryFromTXTRecordData(data)
        guard let portData = dictionary[kInputPortKey] else {
            return nil
        }
        
        var port = UInt16(0)
        portData.getBytes(&port, length: sizeof(UInt16))
        
        if port == 0 {
            return nil
        } else {
            inputPort = CFSwapInt16LittleToHost(port)
        }
    }
    
    func marshal() -> NSData {
        var swappedPort = CFSwapInt16HostToLittle(inputPort)
        let portData = NSData(bytes: &swappedPort, length: sizeof(UInt16))
        return NSNetService.dataFromTXTRecordDictionary([kInputPortKey: portData])
    }
}
