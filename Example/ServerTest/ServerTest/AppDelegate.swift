//
//  AppDelegate.swift
//  ServerTest
//
//  Created by Robin Goos on 27/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Cocoa
import ControllerKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, ServerDelegate, ClientDelegate {

    @IBOutlet weak var window: NSWindow!
    var view: JoystickView!
    var server: Server!
    var client: Client?

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        view = JoystickView()
        window.contentView?.addSubview(view)
        view.frame = window.contentView!.bounds
        server = Server(name: "TestServer", controllerTypes: [.HID, .Remote])
        server.delegate = self
        server.start()
    }
    
    func server(server: Server, controllerConnected controller: Controller, type: ControllerType) {
        print("Found controller: \(controller.state.name.value)")
        client = Client(name: "Test", controller: controller)
        client?.delegate = self
        client?.start()
        
        controller.state.dpad.observe { change in
            self.view.state = change.new
        }
    }
    
    func server(server: Server, controllerDisconnected controller: Controller) {
        print("Disconnected controller: \(controller.state.name.value)")
    }
    
    func server(server: Server, encounteredError error: ErrorType) {
        print(error)
    }
    
    func client(client: Client, discoveredService service: NSNetService) {
        client.connect(service)
    }
    
    func client(client: Client, lostService service: NSNetService) {
        
    }
    
    func client(client: Client, connectedToService service: NSNetService) {
        print("Connected to: \(service.name)")
    }
    
    func client(client: Client, disconnectedFromService service: NSNetService) {
    
    }
    
    func client(client: Client, encounteredError error: ErrorType) {

    }

    func applicationWillTerminate(aNotification: NSNotification) {
    
    }
}

class JoystickView : NSView {
    var state: JoystickState = JoystickState(xAxis: 0, yAxis: 0) {
        didSet {
            needsDisplay = true
        }
    }
    
    override func drawRect(dirtyRect: NSRect) {
        let path = NSBezierPath()
        path.moveToPoint(NSPoint(x: frame.midX, y: frame.midY))
        path.lineToPoint(NSPoint(x: CGFloat(state.xAxis) * frame.midX + frame.midX, y: CGFloat(state.yAxis) * frame.midY + frame.midY))
        NSColor.greenColor().setStroke()
        path.lineWidth = 2.0
        path.stroke()
    }
}

