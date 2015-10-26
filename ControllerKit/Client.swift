//
//  Client.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/*!
    @class Client
    
    @abstract
    Client represents a controller published over the network associated
    to a certain service. The Client is instantiated with a serviceIdentifier, a 1-15 
    character long string which must match the identifier that another node is browsing
    after.
*/
public final class Client {
    var name: String {
        return peerId.displayName
    }
    
    let peerId: MCPeerID
    let advertiser: MCNearbyServiceAdvertiser
    let controller: Controller
    
    public init(name: String, serviceIdentifier: String = "ckit-client", controller: Controller) {
        peerId = MCPeerID(displayName: name)
        advertiser = MCNearbyServiceAdvertiser(peer: peerId, discoveryInfo: nil, serviceType: serviceIdentifier)
        self.controller = controller
    }
    
    public func publish() {
        advertiser.startAdvertisingPeer()
    }
    
    public func unpublish() {
        advertiser.stopAdvertisingPeer()
    }
}