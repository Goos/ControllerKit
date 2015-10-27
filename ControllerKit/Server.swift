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

public protocol ServerDelegate {
    func server(server: Server, discoveredController controller: Controller)
    func server(server: Server, disconnectedController controller: Controller)
    func server(server: Server, encounteredError error: NSError)
}

/*! 
    @class Server
    
    @abstract
    Server is represents an entity to which Clients and Controllers can connect.
*/
public final class Server : NSObject, AsyncServerDelegate {
    public var name: String {
        return netServer.serviceName
    }
    
    public private(set) var controllers: [Controller] = []
    public var delegate: ServerDelegate?
    
    private var nativeControllers: [GCController:Controller] = [:]
    private var remoteControllers: [AsyncConnection:Controller] = [:]
    
    private let netServer: AsyncServer
    private let inputQueue = dispatch_queue_create("com.controllerkit.input_queue", DISPATCH_QUEUE_SERIAL)
    private let queueable: DispatchQueueable
    
    public init(name: String, serviceIdentifier: String = "controllerkit") {
        queueable = inputQueue.queueable()
        netServer = AsyncServer()
        netServer.serviceName = name
        netServer.serviceType = "_\(serviceIdentifier)._tcp"
        super.init()
        
        netServer.delegate = self
    }
    
    public func publish() {
        netServer.start()
        GCController.startWirelessControllerDiscoveryWithCompletionHandler(nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "controllerDidConnect:", name: GCControllerDidConnectNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "controllerDidDisconnect:", name: GCControllerDidDisconnectNotification, object: nil)
    }
    
    public func unpublish() {
        netServer.stop()
        GCController.stopWirelessControllerDiscovery()
        NSNotificationCenter.defaultCenter().removeObserver(self, name: GCControllerDidConnectNotification, object: nil)
    }
    
    // MARK: GCController discovery
    func controllerDidConnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController {
            let controller = Controller(nativeController: nativeController, queue: queueable)
            nativeControllers[nativeController] = controller
            delegate?.server(self, discoveredController: controller)
        }
    }
    
    func controllerDidDisconnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController, controller = nativeControllers[nativeController] {
            controller.inputHandler.send(ConnectionChanged(status: .Disconnected))
        }
    }
    
    // MARK: AsyncServerDelegate
    public func server(theServer: AsyncServer!, didConnect connection: AsyncConnection!) {
        let inputHandler = Actor(initialState: ControllerState(), interactors: [RemoteControllerInteractor], reducer: ControllerStateReducer, processingQueue: queueable)
        let controller = Controller(inputHandler: inputHandler)
        remoteControllers[connection] = controller
        delegate?.server(self, discoveredController: controller)
    }
    
    public func server(theServer: AsyncServer!, didDisconnect connection: AsyncConnection!) {
        if let controller = remoteControllers[connection] {
            controller.inputHandler.send(ConnectionChanged(status: .Disconnected))
            NSTimer.setTimeout(12) { [weak self] in
                self?.delegate?.server(self!, disconnectedController: controller)
                self?.remoteControllers.removeValueForKey(connection)
            }
        }
    }
    
    public func server(theServer: AsyncServer!, didFailWithError error: NSError!) {
        delegate?.server(self, encounteredError: error)
    }
    
    public func server(theServer: AsyncServer!, didReceiveCommand command: AsyncCommand, object: AnyObject!, connection: AsyncConnection!) {
        if let controller = remoteControllers[connection] {
            let message = RemoteSessionMessage(command: command, data: object)
            controller.inputHandler.send(message)
        }
    }
}