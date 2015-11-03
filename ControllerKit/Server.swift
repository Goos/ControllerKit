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
    private var mfiControllers: [GCController:Controller] = [:]
    private var remoteControllers: [String:Controller] = [:]
    private var hidControllers: Set<Controller> = []
    
    private let controllerTypes: Set<ControllerType>
    
    private var netService: NSNetService?
    private let discoverySocket: GCDAsyncSocket
    private let inputConnection: UDPConnection
    
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
                netService = NSNetService(domain: kLocalDomain, type: "_\(serviceIdentifier)._tcp", name: name, port: Int32(port))
                netService?.delegate = self
                netService?.includesPeerToPeer = false
                netService?.publish()
                
                inputConnection.listen(5126)
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
    
    func setupInputConnection() {
    }
    
    // MARK: GCController discovery
    func controllerDidConnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController {
            if let existing = mfiControllers[nativeController] {
                existing.inputHandler.send(ConnectionChanged(status: .Connected))
            } else {
                let controller = Controller(nativeController: nativeController, queue: queueable)
                controller.state.name.value = "Controller \(controllers.count + 1)"
                mfiControllers[nativeController] = controller
                delegate?.server(self, controllerConnected: controller, type: .MFi)
            }
        }
    }
    
    func controllerDidDisconnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController, controller = mfiControllers[nativeController] {
            controller.inputHandler.send(ConnectionChanged(status: .Disconnected))
            
            NSTimer.setTimeout(12) { [weak self] in
                if controller.state.status == .Disconnected {
                    self?.delegate?.server(self!, controllerDisconnected: controller)
                    self?.mfiControllers.removeValueForKey(nativeController)
                }
            }
        }
    }
    
    // MARK: HIDManagerDelegate
    func manager(manager: HIDControllerManager, controllerConnected controller: Controller) {
        hidControllers.insert(controller)
        self.delegate?.server(self, controllerConnected: controller, type: .HID)
    }
    
    func manager(manager: HIDControllerManager, controllerDisconnected controller: Controller) {
        hidControllers.remove(controller)
        self.delegate?.server(self, controllerDisconnected: controller)
    }
    
    func manager(manager: HIDControllerManager, failedWithError error: HIDManagerError) {
    }
    
    // MARK: NSNetServiceDelegate
    public func netServiceDidPublish(sender: NSNetService) {
        
    }
    
    public func netService(sender: NSNetService, didNotPublish errorDict: [String : NSNumber]) {

    }
    
    public func netServiceDidStop(sender: NSNetService) {

    }
    
    // MARK: GCDAsyncSocketDelegate
    public func socket(sock: GCDAsyncSocket!, didAcceptNewSocket newSocket: GCDAsyncSocket!) {
        let tcpConnection = TCPConnection(socket: newSocket, delegateQueue: inputQueue)
        connections.insert(tcpConnection)
        
        let host = newSocket.connectedHost
        let port = newSocket.connectedPort
        
        guard let nc = tcpConnection.registerReadChannel(1, type: SetControllerName.self),
            gc = tcpConnection.registerReadChannel(2, type: SetGamepadType.self),
            jc = inputConnection.registerReadChannel(3, host: host, type: JoystickChanged.self),
            bc =  inputConnection.registerReadChannel(4, host: host, type: ButtonChanged.self) else {
            // TODO: Handle error
            return
        }
        
        
        let inputHandler = ControllerInputHandler(GamepadState(type: .Regular), processingQueue: inputQueue.queueable())
        let controller = Controller(inputHandler: inputHandler)
        let key = "\(host):\(port)"
        remoteControllers[key] = controller
        
        nc.receive {
            inputHandler.send($0)
        }
        
        gc.receive {
            inputHandler.send($0)
        }
        
        jc.receive {
            if let controller = self.remoteControllers.values.first {
                controller.inputHandler.send($0)
            }
        }
        
        bc.receive {
            if let controller = self.remoteControllers.values.first {
                controller.inputHandler.send($0)
            }
        }
        
        tcpConnection.onDisconnect = {
            self.connections.remove(tcpConnection)
            self.remoteControllers.removeValueForKey(key)
            self.delegate?.server(self, controllerDisconnected: controller)
            tcpConnection.deregisterReadChannel(nc)
            tcpConnection.deregisterReadChannel(gc)
            self.inputConnection.deregisterReadChannel(jc)
            self.inputConnection.deregisterReadChannel(bc)
        }
        
        tcpConnection.onError = { err in
            self.delegate?.server(self, encounteredError: err)
        }
        
        self.delegate?.server(self, controllerConnected: controller, type: .Remote)
    }
}