//
//  Client.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

@objc public protocol ClientDelegate : class {
    func client(client: Client, discoveredService service: NSNetService)
    func client(client: Client, lostService service: NSNetService)
    
    func client(client: Client, connectedToService service: NSNetService)
    func client(client: Client, disconnectedFromService service: NSNetService)
    func client(client: Client, encounteredError error: NSError)
}

/*!
    @class Client
    
    @abstract
    Client represents a controller published over the network associated
    to a certain service. The Client is instantiated with a serviceIdentifier, a 1-15 
    character long string which must match the identifier that another node is browsing
    after.
*/
public final class Client : NSObject, NSNetServiceBrowserDelegate, NSNetServiceDelegate {
    let name: String
    let serviceIdentifier: String
    
    internal(set) var controllers: [UInt16:Controller] = [:]
    private var observerBlocks: [UInt16:()->()] = [:]
    
    let browser: NSNetServiceBrowser
    private var currentService: NSNetService?
    
    let tcpConnection: TCPConnection
    let inputConnection: UDPConnection
    
    var connectChannel: WriteChannel<ControllerConnectedMessage>?
    let nameChannel: WriteChannel<RemoteMessage<ControllerNameMessage>>
    var gamepadChannel: WriteChannel<RemoteMessage<GamepadMessage>>?
    
    let networkQueue = dispatch_queue_create("com.controllerkit.network", DISPATCH_QUEUE_SERIAL)
    let delegateQueue = dispatch_queue_create("com.controllerkit.delegate", DISPATCH_QUEUE_SERIAL)
    
    public weak var delegate: ClientDelegate?
    
    public init(name: String, serviceIdentifier: String = "controllerkit", controllers: [Controller]) {
        self.name = name
        self.serviceIdentifier = serviceIdentifier
        
        browser = NSNetServiceBrowser()
        browser.includesPeerToPeer = false
        tcpConnection = TCPConnection(socketQueue: networkQueue, delegateQueue: delegateQueue)
        inputConnection = UDPConnection(socketQueue: networkQueue, delegateQueue: delegateQueue)
        
        connectChannel = tcpConnection.registerWriteChannel(1, type: ControllerConnectedMessage.self)
        nameChannel = tcpConnection.registerWriteChannel(2, type: RemoteMessage<ControllerNameMessage>.self)
        
        super.init()
        
        for controller in controllers {
            addController(controller)
        }
        
        browser.delegate = self
    }
    
    public func addController(controller: Controller) {
        if controllers[controller.index] == nil {
            controllers[controller.index] = controller
            let throttler = ThrottledBuffer<GamepadState>(interval: 1.0/60.0, handler: { gamepad in
                let message = RemoteMessage(message: GamepadMessage(state: gamepad), controllerIndex: controller.index)
                self.gamepadChannel?.send(message)
            })
            
            observerBlocks[controller.index] = controller.inputHandler.observe { gamepad in
                throttler.insert(gamepad)
            }
            
            if currentService != nil {
                for (index, controller) in controllers {
                    let message = ControllerConnectedMessage(index: index, layout: controller.layout, name: controller.name)
                    connectChannel?.send(message)
                }
            }
        }
    }
    
    public func removeController(controller: Controller) {
        observerBlocks[controller.index]?()
        controllers.removeValueForKey(controller.index)
        observerBlocks.removeValueForKey(controller.index)
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
        self.delegate?.client(self, discoveredService: service)
    }
    
    public func netServiceBrowser(browser: NSNetServiceBrowser, didRemoveService service: NSNetService, moreComing: Bool) {
        self.delegate?.client(self, lostService: service)
    }
    
    public func netServiceBrowser(browser: NSNetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        if let code = errorDict[NSNetServicesErrorCode] as? Int {
            let error = NSError(domain: "com.controllerkit.netservice", code: code, userInfo: errorDict)
            self.delegate?.client(self, encounteredError: error)
        }
    }
    
    // MARK: NSNetServiceDelegate
    public func netServiceDidResolveAddress(sender: NSNetService) {
        guard let address = sender.addresses?.first,
            txtRecordData = sender.TXTRecordData(),
            txtRecord = ServerTXTRecord(data: txtRecordData) else {
            return
        }
        
        tcpConnection.connect(address, success: { [weak self] in
            guard let client = self else {
                return
            }
            let host = client.tcpConnection.socket.connectedHost
            let port = UInt16(txtRecord.inputPort)
            self?.gamepadChannel = client.inputConnection.registerWriteChannel(3, host: host, port: port, type: RemoteMessage<GamepadMessage>.self)
            for (index, controller) in client.controllers {
                let message = ControllerConnectedMessage(index: index, layout: controller.layout, name: controller.name)
                client.connectChannel?.send(message)
            }
        }, error: { [weak self] error in
            if let s = self {
                s.delegate?.client(s, encounteredError: error)
            }
        }, disconnect: { [weak self] in
            if let s = self {
                s.delegate?.client(s, disconnectedFromService: sender)
            }
        })
        
    }
    
    public func netService(sender: NSNetService, didNotResolve errorDict: [String : NSNumber]) {
        if let code = errorDict[NSNetServicesErrorCode] as? Int {
            let error = NSError(domain: "com.controllerkit.netservice", code: code, userInfo: errorDict)
            self.delegate?.client(self, encounteredError: error)
        }
    }
}