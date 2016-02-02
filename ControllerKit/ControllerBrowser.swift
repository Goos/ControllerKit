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

protocol ControllerSource {
    func listen(controllerConnected: (Controller) -> (), controllerDisconnected: (Controller) -> (), error: (NSError) -> ())
    func stop()
}

@objc public protocol ControllerBrowserDelegate : class {
    func controllerBrowser(browser: ControllerBrowser, controllerConnected controller: Controller)
    func controllerBrowser(browser: ControllerBrowser, controllerDisconnected controller: Controller)
    func controllerBrowser(browser: ControllerBrowser, encounteredError error: NSError)
}

@objc public enum ControllerType : Int {
    case MFi
    case HID
    case Remote
}
/*!
    @class Server
    
    @abstract
    Server is represents an entity to which Clients and Controllers can connect.
*/
public final class ControllerBrowser : NSObject, NSNetServiceDelegate {
    public let name: String
    public let serviceIdentifier: String
    public weak var delegate: ControllerBrowserDelegate?
    
    private let controllerTypes: Set<ControllerType>
    
    private(set) public var controllers: [Controller] = []
    
    private var controllerSources: [ControllerSource] = []
    
    private let networkQueue = dispatch_queue_create("com.controllerkit.network_queue", DISPATCH_QUEUE_SERIAL)
    private let inputQueue = dispatch_queue_create("com.controllerkit.input_queue", DISPATCH_QUEUE_SERIAL)
    
    public convenience init(name: String) {
        self.init(name: name, controllerTypes: [.Remote, .HID, .MFi])
    }
    
    public init(name: String, serviceIdentifier: String = "controllerkit", controllerTypes: Set<ControllerType>) {
        self.name = name
        self.serviceIdentifier = serviceIdentifier
        self.controllerTypes = controllerTypes
        
        if controllerTypes.contains(.MFi) {
            controllerSources.append(MFiControllerSource(queue: inputQueue.queueable()))
        }
        if controllerTypes.contains(.Remote) {
            controllerSources.append(NetworkControllerSource(name: name, networkQueue: networkQueue, inputQueue: inputQueue))
        }
        if controllerTypes.contains(.HID) {
            #if os(OSX)
            controllerSources.append(HIDControllerSource())
            #endif
        }
        
        super.init()
    }
    
    public func start() {
        for source in controllerSources {
            source.listen({ [weak self] controller in
                self?.addController(controller)
            }, controllerDisconnected: { [weak self] controller in
                self?.removeController(controller)
            }, error: { [weak self] error in
                if let s = self {
                    dispatch_async(dispatch_get_main_queue()) {
                        s.delegate?.controllerBrowser(s, encounteredError: error)
                    }
                }
            })
        }
    }
    
    public func stop() {
        for source in controllerSources {
            source.stop()
        }
    }
    
    private func addController(controller: Controller) {
        controllers.append(controller)
        controller.index = UInt16(controllers.count)
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate?.controllerBrowser(self, controllerConnected: controller)
        }
    }
    
    private func removeController(controller: Controller) {
        if let idx = controllers.indexOf(controller) {
            controllers.removeAtIndex(idx)
            for (index, ctrlrs) in controllers.enumerate() {
                ctrlrs.index = UInt16(index)
            }
            
            dispatch_async(dispatch_get_main_queue()) {
                self.delegate?.controllerBrowser(self, controllerDisconnected: controller)
            }
        }
    }
}

