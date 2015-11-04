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

public protocol ServerDelegate : class {
    func server(server: Server, controllerConnected controller: Controller, type: ControllerType)
    func server(server: Server, controllerDisconnected controller: Controller)
    func server(server: Server, encounteredError error: ErrorType)
}

public enum ControllerType {
    case MFi
    case HID
    case Remote
}

public struct NetServiceError : ErrorType {
    let domain: Int
    let code: Int
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

final class InputChannelSet {
    var controllers: [UInt16:Controller] = [:]
    let nameChannel: ReadChannel<RemoteMessage<SetControllerName>>
    let gamepadTypeChannel: ReadChannel<RemoteMessage<SetGamepadType>>
    let joystickChannel: ReadChannel<RemoteMessage<JoystickChanged>>
    let buttonChannel: ReadChannel<RemoteMessage<ButtonChanged>>
    
    init(nameChannel: ReadChannel<RemoteMessage<SetControllerName>>, gamepadTypeChannel: ReadChannel<RemoteMessage<SetGamepadType>>, joystickChannel: ReadChannel<RemoteMessage<JoystickChanged>>, buttonChannel: ReadChannel<RemoteMessage<ButtonChanged>>) {
        self.nameChannel = nameChannel
        self.gamepadTypeChannel = gamepadTypeChannel
        self.joystickChannel = joystickChannel
        self.buttonChannel = buttonChannel
        
        nameChannel.receive { message in
            if let controller = self.controllers[message.controllerIdx] {
                controller.inputHandler.send(message.message)
            }
        }
        
        gamepadTypeChannel.receive { message in
            if let controller = self.controllers[message.controllerIdx] {
                controller.inputHandler.send(message.message)
            }
        }
        
        joystickChannel.receive { message in
            if let controller = self.controllers[message.controllerIdx] {
                controller.inputHandler.send(message.message)
            }
        }
        
        buttonChannel.receive { message in
            if let controller = self.controllers[message.controllerIdx] {
                controller.inputHandler.send(message.message)
            }
        }
    }
    
    func append(controller: Controller) {
        controller.index = UInt16(controllers.count)
        controllers[controller.index] = controller
    }
    
    func remove(controller: Controller) {
        controllers.removeValueForKey(controller.index)
    }
}

let kLocalDomain = "local."

/*! 
    @class Server
    
    @abstract
    Server is represents an entity to which Clients and Controllers can connect.
*/
public final class Server : NSObject, HIDManagerDelegate, NSNetServiceDelegate, GCDAsyncSocketDelegate {
    public let name: String
    public let serviceIdentifier: String
    public weak var delegate: ServerDelegate?
    
    public var controllers: [Controller] {
        return [Array(mfiControllers.values), Array(remoteControllers.values), Array(hidControllers)].flatMap { $0 }
    }
    private var mfiControllers: [GCControllerPlayerIndex:Controller] = [:]
    private var remoteControllers: [String:Controller] = [:]
    private var hidControllers: Set<Controller> = []
    
    private let controllerTypes: Set<ControllerType>
    
    private var netService: NSNetService?
    private let discoverySocket: GCDAsyncSocket
    private let inputConnection: UDPConnection
    private var inputChannels: [String:InputChannelSet] = [:]
    
    private var connections: Set<TCPConnection> = []
    
    private let hidManager: HIDControllerManager
    
    private let networkQueue = dispatch_queue_create("com.controllerkit.network_queue", DISPATCH_QUEUE_CONCURRENT)
    private let inputQueue = dispatch_queue_create("com.controllerkit.input_queue", DISPATCH_QUEUE_SERIAL)
    private let queueable: DispatchQueueable
    
    public init(name: String, serviceIdentifier: String = "controllerkit", controllerTypes: Set<ControllerType> = [.MFi, .HID, .Remote]) {
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
                    self.delegate?.server(self, encounteredError: err)
                })
            } catch let error as NSError {
                self.delegate?.server(self, encounteredError: error)
            } catch {}
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
    
    // MARK: GCController discovery
    func controllerDidConnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController {
            if let existing = mfiControllers[nativeController.playerIndex] {
                existing.inputHandler.send(ConnectionChanged(status: .Connected))
            } else {
                let controller = Controller(nativeController: nativeController, queue: queueable)
                controller.index = UInt16(controllers.count)
                mfiControllers[nativeController.playerIndex] = controller
                delegate?.server(self, controllerConnected: controller, type: .MFi)
            }
        }
    }
    
    func controllerDidDisconnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController, controller = mfiControllers[nativeController.playerIndex] {
            controller.inputHandler.send(ConnectionChanged(status: .Disconnected))
            
            NSTimer.setTimeout(12) { [weak self] in
                if controller.state.status == .Disconnected {
                    self?.delegate?.server(self!, controllerDisconnected: controller)
                    self?.mfiControllers.removeValueForKey(nativeController.playerIndex)
                }
            }
        }
    }
    
    // MARK: HIDManagerDelegate
    func manager(manager: HIDControllerManager, controllerConnected controller: Controller) {
        controller.index = UInt16(controllers.count)
        hidControllers.insert(controller)
        self.delegate?.server(self, controllerConnected: controller, type: .HID)
    }
    
    func manager(manager: HIDControllerManager, controllerDisconnected controller: Controller) {
        hidControllers.remove(controller)
        self.delegate?.server(self, controllerDisconnected: controller)
    }
    
    func manager(manager: HIDControllerManager, failedWithError error: HIDManagerError) {
        self.delegate?.server(self, encounteredError: error)
    }
    
    // MARK: NSNetServiceDelegate
    public func netServiceDidPublish(sender: NSNetService) {
        
    }
    
    public func netService(sender: NSNetService, didNotPublish errorDict: [String : NSNumber]) {
        if let domain = errorDict[NSNetServicesErrorDomain] as? Int,
            code = errorDict[NSNetServicesErrorCode] as? Int {
                self.delegate?.server(self, encounteredError: NetServiceError(domain: domain, code: code))
        }
    }
    
    public func netServiceDidStop(sender: NSNetService) {

    }
    
    // MARK: GCDAsyncSocketDelegate
    public func socket(sock: GCDAsyncSocket!, didAcceptNewSocket newSocket: GCDAsyncSocket!) {
        let tcpConnection = TCPConnection(socket: newSocket, delegateQueue: inputQueue)
        connections.insert(tcpConnection)
        
        let host = newSocket.connectedHost
        
        var channelSet: InputChannelSet
        if let cs = inputChannels[host] {
            channelSet = cs
        } else if let nc = tcpConnection.registerReadChannel(1, type: RemoteMessage<SetControllerName>.self),
            gc = tcpConnection.registerReadChannel(2, type: RemoteMessage<SetGamepadType>.self),
            jc = inputConnection.registerReadChannel(3, host: host, type: RemoteMessage<JoystickChanged>.self),
            bc =  inputConnection.registerReadChannel(4, host: host, type: RemoteMessage<ButtonChanged>.self) {
            channelSet = InputChannelSet(nameChannel: nc, gamepadTypeChannel: gc, joystickChannel: jc, buttonChannel: bc)
            inputChannels[host] = channelSet
        } else {
            return
        }
        
        let inputHandler = ControllerInputHandler(GamepadState(type: .Regular), processingQueue: inputQueue.queueable())
        let controller = Controller(inputHandler: inputHandler)
        controller.index = UInt16(controllers.count)
        
        channelSet.append(controller)
        
        tcpConnection.onDisconnect = {
            channelSet.remove(controller)
            self.connections.remove(tcpConnection)
            self.delegate?.server(self, controllerDisconnected: controller)
            if channelSet.controllers.count == 0 {
                self.inputConnection.deregisterReadChannel(channelSet.joystickChannel)
                self.inputConnection.deregisterReadChannel(channelSet.gamepadTypeChannel)
                self.inputChannels.removeValueForKey(host)
            }
        }
        
        tcpConnection.onError = { err in
            self.delegate?.server(self, encounteredError: err)
        }
        
        self.delegate?.server(self, controllerConnected: controller, type: .Remote)
    }
}