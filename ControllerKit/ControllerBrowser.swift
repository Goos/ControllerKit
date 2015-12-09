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
    let host: String
    let nameChannel: TCPReadChannel<RemoteMessage<ControllerNameMessage>>
    let gamepadChannel: UDPReadChannel<RemoteMessage<GamepadMessage>>
    
    init(host: String, nameChannel: TCPReadChannel<RemoteMessage<ControllerNameMessage>>, gamepadChannel: UDPReadChannel<RemoteMessage<GamepadMessage>>) {
        self.host = host
        self.nameChannel = nameChannel
        self.gamepadChannel = gamepadChannel
        
        nameChannel.onReceive = { [weak self] message in
            if let controller = self?.controllers[message.controllerIndex] {
                controller.name = message.message.name
            }
        }
        
        gamepadChannel.onReceive = { [weak self] message in
            if let controller = self?.controllers[message.controllerIndex] {
                controller.inputHandler.send(message.message)
            }
        }
    }
}

let kLocalDomain = "local."

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
        self.init(name: name, controllerTypes: [.Remote, .HID, .MFi])
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
        connections.insert(tcpConnection)
        
        let host = newSocket.connectedHost
        
        if let peer = remotePeers[host] {
            self.remotePeerReconnected(peer)
        } else {
            let cc = tcpConnection.registerReadChannel(1, type: ControllerConnectedMessage.self)
            let dc = tcpConnection.registerReadChannel(2, type: ControllerDisconnectedMessage.self)
            
            cc.onReceive = { [weak self, unowned tcpConnection] message in
                if let s = self {
                    s.receivedControllerConnectedMessage(message, connection: tcpConnection)
                }
            }
            
            dc.onReceive = { [weak self, unowned tcpConnection] message in
                if let s = self {
                    s.receivedControllerDisconnectedMessage(message, connection: tcpConnection)
                }
            }
        }
        
        tcpConnection.onDisconnect = { [weak self] in
            if let peer = self?.remotePeers[host] {
                self?.remotePeerDisconnected(peer)
            }
        }
        
        tcpConnection.onError = { [weak self] err in
            self?.delegate?.controllerBrowser(self!, encounteredError: err)
        }
    }
    
    public func newSocketQueueForConnectionFromAddress(address: NSData!, onSocket sock: GCDAsyncSocket!) -> dispatch_queue_t! {
        return networkQueue
    }
    
    private func receivedControllerConnectedMessage(message: ControllerConnectedMessage, connection: TCPConnection) {
        let host = connection.socket.connectedHost
        var peer = remotePeers[host]
        if peer == nil {
            // Registering a channel on the TCP connection for controller name changes.
            let nc = connection.registerReadChannel(3, type: RemoteMessage<ControllerNameMessage>.self)
            /* Registering a channel on the open UDP connection, listening
                for controller input from this specific host. */
            let gc = inputConnection.registerReadChannel(1, host: host, type: RemoteMessage<GamepadMessage>.self)
            
            peer = RemotePeer(host: host, nameChannel: nc, gamepadChannel: gc)
            remotePeers[host] = peer
        }
        
        if let controller = peer!.controllers[message.index] {
            controller.status = .Connected
        } else {
            let inputHandler = ControllerInputHandler(GamepadState(layout: .Regular), processingQueue: self.inputQueue.queueable())
            let controller = Controller(inputHandler: inputHandler)
            controller.index = UInt16(self.controllers.count)
            peer!.controllers[message.index] = controller
            
            self.delegate?.controllerBrowser(self, controllerConnected: controller, type: .Remote)
        }
    }
    
    private func receivedControllerDisconnectedMessage(message: ControllerDisconnectedMessage, connection: TCPConnection) {
        let host = connection.socket.connectedHost
        guard let peer = remotePeers[host] else {
            return
        }
        
        if let controller = peer.controllers[message.index] {
            self.delegate?.controllerBrowser(self, controllerDisconnected: controller)
            peer.controllers.removeValueForKey(message.index)
        }
    }
    
    /* Whenever a peer disconnects, it has a short grace period before
        the delegate is notified that the controllers are disconnected.
        This is in order to make it slightly more resilient to network
        drops and the likes. */
    private func remotePeerDisconnected(peer: RemotePeer) {
        for (_, controller) in peer.controllers {
            controller.status = .Disconnected
        }
        
        NSTimer.setTimeout(12) {
            for (index, controller) in peer.controllers {
                if controller.status == .Disconnected {
                    self.delegate?.controllerBrowser(self, controllerDisconnected: controller)
                    peer.controllers.removeValueForKey(index)
                }
            }
            
            if peer.controllers.count == 0 {
                self.inputConnection.deregisterReadChannel(peer.gamepadChannel)
                self.remotePeers.removeValueForKey(peer.host)
            }
        }
    }
    
    /* If the peer reconnects before a short timer, the controllers
        are reconnected. */
    private func remotePeerReconnected(peer: RemotePeer) {
        for (_, controller) in peer.controllers {
            controller.status = .Connected
        }
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
