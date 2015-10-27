//
//  Client.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

public protocol ClientDelegate {
    func client(client: Client, discoveredService service: NSNetService)
    func client(client: Client, lostService service: NSNetService)
    func clientLostConnection(client: Client)
}

/*!
    @class Client
    
    @abstract
    Client represents a controller published over the network associated
    to a certain service. The Client is instantiated with a serviceIdentifier, a 1-15 
    character long string which must match the identifier that another node is browsing
    after.
*/
public final class Client : NSObject, AsyncClientDelegate {
    let name: String
    let netClient: AsyncClient
    let controller: Controller
    var onConnect: (() -> ())?
    var onError: ((NSError) -> ())?
    
    public var delegate: ClientDelegate?
    
    public init(name: String, serviceIdentifier: String = "controllerkit", controller: Controller) {
        self.name = name
        self.controller = controller
        
        netClient = AsyncClient()
        netClient.autoConnect = false
        netClient.serviceType = "_\(serviceIdentifier)._tcp"
        
        super.init()
        
        netClient.delegate = self
        
        controller.state.buttonA.observe { self.buttonChanged(.A, state: $0.new) }
        controller.state.buttonB.observe { self.buttonChanged(.B, state: $0.new) }
        controller.state.buttonX.observe { self.buttonChanged(.X, state: $0.new) }
        controller.state.buttonY.observe { self.buttonChanged(.Y, state: $0.new) }
        controller.state.leftShoulder.observe { self.buttonChanged(.LS, state: $0.new) }
        controller.state.rightShoulder.observe { self.buttonChanged(.RS, state: $0.new) }
        controller.state.dpad.observe { self.dpadChanged($0.new) }
    }
    
    public func publish() {
        netClient.start()
    }
    
    public func unpublish() {
        netClient.stop()
    }
    
    public func connect(service: NSNetService, success: (() -> ())? = nil, error: ((NSError) -> ())? = nil) {
        onConnect = success
        onError = error
        netClient.connectToService(service)
    }
    
    // MARK: AsyncClientDelegate
    // Service discovery
    public func client(theClient: AsyncClient!, didFindService service: NSNetService!, moreComing: Bool) -> Bool {
        delegate?.client(self, discoveredService: service)
        return false
    }
    
    public func client(theClient: AsyncClient!, didRemoveService service: NSNetService!) {
        delegate?.client(self, lostService: service)
    }
    
    // Service connection
    public func client(theClient: AsyncClient!, didConnect connection: AsyncConnection!) {
        onConnect?()
        onError = nil
        onConnect = nil
    }
    
    public func client(theClient: AsyncClient!, didFailWithError error: NSError!) {
        onError?(error)
        onError = nil
        onConnect = nil
    }
    
    public func client(theClient: AsyncClient!, didDisconnect connection: AsyncConnection!) {
        delegate?.clientLostConnection(self)
    }
    
    // MARK: Input forwarding
    func buttonChanged(button: ButtonType, state: ButtonState) {
        let message = ButtonChanged(button: button, state: state)
        netClient.sendCommand(1, object: message)
    }
    
    func dpadChanged(state: DpadState) {
        let message = DpadChanged(state: state)
        netClient.sendCommand(1, object: message)
    }
}