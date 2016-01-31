//
//  ControllerPublisher.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

@objc public protocol ControllerPublisherDelegate : class {
    func publisher(publisher: ControllerPublisher, discoveredService service: NSNetService)
    func publisher(publisher: ControllerPublisher, lostService service: NSNetService)
    
    func publisher(publisher: ControllerPublisher, connectedToService service: NSNetService)
    func publisher(publisher: ControllerPublisher, disconnectedFromService service: NSNetService)
    func publisher(publisher: ControllerPublisher, encounteredError error: NSError)
}

/*!
    @class ControllerPublisher
    
    @abstract
    The publisher represents a controller over the network associated
    to a certain service. The publisher is instantiated with a serviceIdentifier, a 1-15
    character long string which must match the identifier that another node is browsing
    after.
*/
public final class ControllerPublisher : NSObject, NSNetServiceBrowserDelegate, NSNetServiceDelegate {
    let name: String
    let serviceIdentifier: String
    
    internal(set) var controllers: [UInt16:Controller] = [:]
    private var observerBlocks: [UInt16:()->()] = [:]
    
    let browser: NSNetServiceBrowser
    private var currentService: NSNetService?
    
    let tcpConnection: TCPConnection
    let inputConnection: UDPConnection
    
    let connectChannel: TCPWriteChannel<ControllerConnectedMessage>
    let disconnectChannel: TCPWriteChannel<ControllerDisconnectedMessage>
    let nameChannel: TCPWriteChannel<NetworkMessage<ControllerNameMessage>>
    var gamepadChannel: UDPWriteChannel<NetworkMessage<GamepadMessage>>?
    
    let networkQueue = dispatch_queue_create("com.controllerkit.network", DISPATCH_QUEUE_SERIAL)
    let delegateQueue = dispatch_queue_create("com.controllerkit.delegate", DISPATCH_QUEUE_SERIAL)
    
    public weak var delegate: ControllerPublisherDelegate?
    
    public init(name: String, serviceIdentifier: String = "controllerkit", controllers: [Controller]) {
        self.name = name
        self.serviceIdentifier = serviceIdentifier
        
        browser = NSNetServiceBrowser()
        browser.includesPeerToPeer = false
        tcpConnection = TCPConnection(socketQueue: networkQueue, delegateQueue: delegateQueue)
        inputConnection = UDPConnection(socketQueue: networkQueue, delegateQueue: delegateQueue)
        
        connectChannel = tcpConnection.registerWriteChannel(1, type: ControllerConnectedMessage.self)
        disconnectChannel = tcpConnection.registerWriteChannel(2, type: ControllerDisconnectedMessage.self)
        nameChannel = tcpConnection.registerWriteChannel(3, type: NetworkMessage<ControllerNameMessage>.self)
        
        super.init()
        
        for controller in controllers {
            addController(controller)
        }
        
        browser.delegate = self
    }
    
    public func addController(controller: Controller) {
        if controllers[controller.index] == nil {
            controllers[controller.index] = controller
            
            observerBlocks[controller.index] = controller.inputHandler.observe { gamepad in
                let message = NetworkMessage(message: GamepadMessage(state: gamepad), controllerIndex: controller.index)
                self.gamepadChannel?.send(message)
            }
            
            if currentService != nil {
                let message = ControllerConnectedMessage(index: controller.index, layout: controller.layout, name: "\(self.name).\(controller.name)")
                connectChannel.send(message)
            }
        }
    }
    
    public func removeController(controller: Controller) {
        observerBlocks[controller.index]?()
        controllers.removeValueForKey(controller.index)
        observerBlocks.removeValueForKey(controller.index)
        
        if currentService != nil {
            let message = ControllerDisconnectedMessage(index: controller.index)
            disconnectChannel.send(message)
        }
    }
    
    public func start() {
        dispatch_async(dispatch_get_main_queue()) {
            self.browser.searchForServicesOfType("_\(self.serviceIdentifier)._tcp", inDomain: kLocalDomain)
        }
    }
    
    public func stop() {
        browser.stop()
    }
    
    public func connect(service: NSNetService) {
        self.currentService = service
        service.delegate = self
        
        dispatch_async(dispatch_get_main_queue()) {
            service.resolveWithTimeout(30)
        }
    }
    
    // MARK: NSNetServiceBrowserDelegate
    public func netServiceBrowser(browser: NSNetServiceBrowser, didFindService service: NSNetService, moreComing: Bool) {
        self.delegate?.publisher(self, discoveredService: service)
    }
    
    public func netServiceBrowser(browser: NSNetServiceBrowser, didRemoveService service: NSNetService, moreComing: Bool) {
        self.delegate?.publisher(self, lostService: service)
    }
    
    public func netServiceBrowser(browser: NSNetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        if let code = errorDict[NSNetServicesErrorCode] as? Int {
            let error = NSError(domain: "com.controllerkit.netservice", code: code, userInfo: errorDict)
            self.delegate?.publisher(self, encounteredError: error)
        }
    }
    
    // MARK: NSNetServiceDelegate
    public func netServiceDidResolveAddress(sender: NSNetService) {
        guard let address = sender.addresses?.first,
            txtRecordData = sender.TXTRecordData(),
            txtRecord = ServiceTXTRecord(data: txtRecordData) else {
            return
        }
        
        tcpConnection.connect(address, success: { [weak self] in
            guard let publisher = self else {
                return
            }
            
            let host = publisher.tcpConnection.socket.connectedHost
            let port = UInt16(txtRecord.inputPort)
            
            self?.gamepadChannel = publisher.inputConnection.registerWriteChannel(1, host: host, port: port, type: NetworkMessage<GamepadMessage>.self)
            
            for (index, controller) in publisher.controllers {
                let message = ControllerConnectedMessage(index: index, layout: controller.layout, name: "\(self?.name).\(controller.name)")
                publisher.connectChannel.send(message)
            }
        }, error: { [weak self] error in
            if let s = self {
                s.delegate?.publisher(s, encounteredError: error)
            }
        }, disconnect: { [weak self] in
            if let s = self {
                s.delegate?.publisher(s, disconnectedFromService: sender)
            }
        })
        
    }
    
    public func netService(sender: NSNetService, didNotResolve errorDict: [String : NSNumber]) {
        if let code = errorDict[NSNetServicesErrorCode] as? Int {
            let error = NSError(domain: "com.controllerkit.netservice", code: code, userInfo: errorDict)
            self.delegate?.publisher(self, encounteredError: error)
        }
    }
}