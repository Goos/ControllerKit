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
    
    let nameChannel: WriteChannel<RemoteMessage<SetControllerName>>
    let gamepadTypeChannel: WriteChannel<RemoteMessage<SetGamepadType>>
    var joystickChannel: WriteChannel<RemoteMessage<JoystickChanged>>?
    var buttonChannel: WriteChannel<RemoteMessage<ButtonChanged>>?
    
    let networkQueue = dispatch_queue_create("com.controllerkit.network", DISPATCH_QUEUE_SERIAL)
    let delegateQueue = dispatch_queue_create("com.controllerkit.delegate", DISPATCH_QUEUE_SERIAL)
    
    public weak var delegate: ClientDelegate?
    
    public init(name: String, serviceIdentifier: String = "controllerkit", controller: Controller) {
        self.name = name
        self.serviceIdentifier = serviceIdentifier
        self.controller = controller
        
        browser = NSNetServiceBrowser()
        browser.includesPeerToPeer = false
        tcpConnection = TCPConnection(socketQueue: networkQueue, delegateQueue: delegateQueue)
        inputConnection = UDPConnection(socketQueue: networkQueue, delegateQueue: delegateQueue)
        
        nameChannel = tcpConnection.registerWriteChannel(1, type: RemoteMessage<SetControllerName>.self)
        gamepadTypeChannel = tcpConnection.registerWriteChannel(2, type: RemoteMessage<SetGamepadType>.self)
        
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
        let message = RemoteMessage(message: SetControllerName(name: name), controllerIdx: controller.index)
        nameChannel.send(message)
    }
    
    func buttonChanged(button: ButtonType, state: ButtonState?) {
        let message = RemoteMessage(message: ButtonChanged(button: button, state: state), controllerIdx: controller.index)
        buttonChannel?.send(message)
    }
    
    func joystickChanged(joystick: JoystickType, state: JoystickState?) {
        let message = RemoteMessage(message: JoystickChanged(joystick: joystick, state: state), controllerIdx: controller.index)
        joystickChannel?.send(message)
    }
    
    // MARK: NSNetServiceBrowserDelegate
    public func netServiceBrowser(browser: NSNetServiceBrowser, didFindService service: NSNetService, moreComing: Bool) {
        self.delegate?.client(self, discoveredService: service)
    }
    
    public func netServiceBrowser(browser: NSNetServiceBrowser, didRemoveService service: NSNetService, moreComing: Bool) {
        self.delegate?.client(self, lostService: service)
    }
    
    public func netServiceBrowser(browser: NSNetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        if let domain = errorDict[NSNetServicesErrorDomain] as? Int,
            code = errorDict[NSNetServicesErrorCode] as? Int {
                self.delegate?.client(self, encounteredError: NetServiceError(domain: domain, code: code))
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
            let host = self?.tcpConnection.socket.connectedHost
            let port = UInt16(txtRecord.inputPort)
            self?.joystickChannel = self?.inputConnection.registerWriteChannel(3, host: host, port: port, type: RemoteMessage<JoystickChanged>.self)
            self?.buttonChannel = self?.inputConnection.registerWriteChannel(4, host: host, port: port, type: RemoteMessage<ButtonChanged>.self)
            if let name = self?.controller.state.name.value {
                let message = RemoteMessage(message: SetControllerName(name: name), controllerIdx: self!.controller.index)
                self?.nameChannel.send(message)
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
        if let domain = errorDict[NSNetServicesErrorDomain] as? Int,
            code = errorDict[NSNetServicesErrorCode] as? Int {
                self.delegate?.client(self, encounteredError: NetServiceError(domain: domain, code: code))
        }
    }
}