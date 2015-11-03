//
//  Client.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

public protocol ClientDelegate : class {
    func client(client: Client, discoveredService service: NSNetService)
    func client(client: Client, lostService service: NSNetService)
    
    func client(client: Client, connectedToService service: NSNetService)
    func client(client: Client, disconnectedFromService service: NSNetService)
    func client(client: Client, encounteredError error: ErrorType)
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
    
    let controller: Controller
    
    let browser: NSNetServiceBrowser
    private var currentService: NSNetService?
    
    let tcpConnection: TCPConnection
    let inputConnection: UDPConnection
    
    let nameChannel: WriteChannel<SetControllerName>
    let gamepadTypeChannel: WriteChannel<SetGamepadType>
    var joystickChannel: WriteChannel<JoystickChanged>?
    var buttonChannel: WriteChannel<ButtonChanged>?
    
    let networkQueue = dispatch_queue_create("com.controllerkit.network", DISPATCH_QUEUE_CONCURRENT)
    let delegateQueue = dispatch_queue_create("com.controllerkit.delegate", DISPATCH_QUEUE_CONCURRENT)
    
    public weak var delegate: ClientDelegate?
    
    public init(name: String, serviceIdentifier: String = "controllerkit", controller: Controller) {
        self.name = name
        self.serviceIdentifier = serviceIdentifier
        self.controller = controller
        
        browser = NSNetServiceBrowser()
        browser.includesPeerToPeer = false
        tcpConnection = TCPConnection(socketQueue: networkQueue, delegateQueue: delegateQueue)
        inputConnection = UDPConnection(socketQueue: networkQueue, delegateQueue: delegateQueue)
        
        nameChannel = tcpConnection.registerWriteChannel(1, type: SetControllerName.self)
        gamepadTypeChannel = tcpConnection.registerWriteChannel(2, type: SetGamepadType.self)
        
        super.init()
        
        browser.delegate = self
        
        controller.state.name.observe { self.nameChanged($0.new) }
        
        controller.state.buttonA.observe { self.buttonChanged(.A, state: $0.new) }
        controller.state.buttonB.observe { self.buttonChanged(.B, state: $0.new) }
        controller.state.buttonX.observe { self.buttonChanged(.X, state: $0.new) }
        controller.state.buttonY.observe { self.buttonChanged(.Y, state: $0.new) }
        
        controller.state.leftShoulder.observe { self.buttonChanged(.LS, state: $0.new) }
        controller.state.rightShoulder.observe { self.buttonChanged(.RS, state: $0.new) }
        controller.state.leftTrigger.observe { self.buttonChanged(.LT, state: $0.new) }
        controller.state.rightTrigger.observe { self.buttonChanged(.RT, state: $0.new) }
        
        controller.state.dpad.observe { self.joystickChanged(.Dpad, state: $0.new) }
        controller.state.leftThumbstick.observe { self.joystickChanged(.LeftThumbstick, state: $0.new) }
        controller.state.rightThumbstick.observe { self.joystickChanged(.RightThumbstick, state: $0.new) }
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
    
    // MARK: Input forwarding
    func nameChanged(name: String?) {
        nameChannel.send(SetControllerName(name: name))
    }
    
    func buttonChanged(button: ButtonType, state: ButtonState?) {
        buttonChannel?.send(ButtonChanged(button: button, state: state))
    }
    
    func joystickChanged(joystick: JoystickType, state: JoystickState?) {
        joystickChannel?.send(JoystickChanged(joystick: joystick, state: state))
    }
    
    // MARK: NSNetServiceBrowserDelegate
    public func netServiceBrowser(browser: NSNetServiceBrowser, didFindService service: NSNetService, moreComing: Bool) {
        self.delegate?.client(self, discoveredService: service)
    }
    
    public func netServiceBrowser(browser: NSNetServiceBrowser, didRemoveService service: NSNetService, moreComing: Bool) {
        self.delegate?.client(self, lostService: service)
    }
    
    public func netServiceBrowser(browser: NSNetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {

    }
    
    // MARK: NSNetServiceDelegate
    public func netServiceDidResolveAddress(sender: NSNetService) {
        guard let address = sender.addresses?.first else {
            return
        }
        
        tcpConnection.connect(address, success: { [weak self] in
            let host = self?.tcpConnection.socket.connectedHost
            let port = UInt16(5126)
            self?.joystickChannel = self?.inputConnection.registerWriteChannel(3, host: host, port: port, type: JoystickChanged.self)
            self?.buttonChannel = self?.inputConnection.registerWriteChannel(4, host: host, port: port, type: ButtonChanged.self)
        }, error: { error in
        
        }, disconnect: {
        
        })
        
    }
    
    public func netService(sender: NSNetService, didNotResolve errorDict: [String : NSNumber]) {

    }
}