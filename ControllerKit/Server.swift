//
//  Service.swift
//  ControllerKit
//
//  Created by Robin Goos on 25/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import GameController
import Act

public protocol ServerDelegate {
    func service(server: Server, discoveredController controller: Controller)
}

/*! 
    @class Server
    
    @abstract
    Server is represents an entity to which Clients and Controllers can connect.
*/
public final class Server : NSObject, MCNearbyServiceAdvertiserDelegate, MCSessionDelegate {
    public var name: String {
        return peerId.displayName
    }
    
    public private(set) var controllers: [Controller] = []
    public var delegate: ServerDelegate?
    
    private var nativeControllers: [GCController:Controller] = [:]
    private var remoteControllers: [MCPeerID:Controller] = [:]
    
    private let peerId: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let inputQueue = dispatch_queue_create("com.controllerkit.input_queue", DISPATCH_QUEUE_SERIAL)
    
    init(name: String, serviceIdentifier: String = "ckit-server") {
        peerId = MCPeerID(displayName: name)
        session = MCSession(peer: peerId)
        advertiser = MCNearbyServiceAdvertiser(peer: peerId, discoveryInfo: nil, serviceType: serviceIdentifier)
        super.init()
        advertiser.delegate = self
    }
    
    public func publish() {
        advertiser.startAdvertisingPeer()
        GCController.startWirelessControllerDiscoveryWithCompletionHandler(nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "controllerDidConnect:", name: GCControllerDidConnectNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "controllerDidDisconnect:", name: GCControllerDidDisconnectNotification, object: nil)
    }
    
    public func unpublish() {
        advertiser.stopAdvertisingPeer()
        GCController.stopWirelessControllerDiscovery()
        NSNotificationCenter.defaultCenter().removeObserver(self, name: GCControllerDidConnectNotification, object: nil)
    }
    
    // MARK: Controller discovery
    func controllerDidConnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController {
            let controller = Controller(nativeController: nativeController, queue: inputQueue.queueable())
            nativeControllers[nativeController] = controller
        }
    }
    
    func controllerDidDisconnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController, controller = nativeControllers[nativeController] {
            controller.inputHandler.send(ConnectionChanged(status: .Disconnected))
        }
    }
    
    // MARK: MCNearbyServiceAdvertiserDelegate
    public func advertiser(advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: NSData?, invitationHandler: (Bool, MCSession) -> Void) {
        invitationHandler(true, session)
        let inputHandler = Actor(initialState: ControllerState(), interactors: [RemoteControllerInteractor], reducer: ControllerStateReducer, backgroundQueue: inputQueue.queueable())
        let controller = Controller(inputHandler: inputHandler)
        remoteControllers[peerId] =  controller
        delegate?.service(self, discoveredController: controller)
    }
    
    // MARK: MCSessionDelegate
    public func session(session: MCSession, peer peerID: MCPeerID, didChangeState state: MCSessionState) {
        if let controller = remoteControllers[peerID], status = ConnectionStatus(rawValue: state.rawValue) {
            controller.inputHandler.send(ConnectionChanged(status: status))
        }
    }
    
    public func session(session: MCSession, didReceiveData data: NSData, fromPeer peerID: MCPeerID) {
        if let controller = remoteControllers[peerID] {
            controller.inputHandler.send(RemoteSessionMessage(data: data))
        }
    }
    
    public func session(session: MCSession, didReceiveStream stream: NSInputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    public func session(session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, withProgress progress: NSProgress) {}
    
    public func session(session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, atURL localURL: NSURL, withError error: NSError?) {}
    
    public func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?, fromPeer peerID: MCPeerID, certificateHandler: (Bool) -> Void) {}
}