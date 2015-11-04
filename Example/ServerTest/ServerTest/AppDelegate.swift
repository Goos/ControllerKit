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
    var leftStickView: JoystickView!
    var rightStickView: JoystickView!
    var dpadView: JoystickView!
    var server: Server!
    var client: Client?

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        leftStickView = JoystickView()
        rightStickView = JoystickView()
        dpadView = JoystickView()
        
        leftStickView.translatesAutoresizingMaskIntoConstraints = false
        rightStickView.translatesAutoresizingMaskIntoConstraints = false
        dpadView.translatesAutoresizingMaskIntoConstraints = false
        
        window.contentView?.addSubview(leftStickView)
        window.contentView?.addSubview(rightStickView)
        window.contentView?.addSubview(dpadView)
        
        let views = ["leftStickView": leftStickView, "rightStickView": rightStickView, "dpadView": dpadView]
        window.contentView?.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|-(>=30)-[leftStickView(80)]-(16)-[rightStickView(80)]-(>=30)-|", options: [], metrics: nil, views: views))
        window.contentView?.addConstraint(NSLayoutConstraint(item: leftStickView, attribute: .CenterX, relatedBy: .Equal, toItem: window.contentView, attribute: .CenterX, multiplier: 1.0, constant: -44.0))
        window.contentView?.addConstraint(NSLayoutConstraint(item: dpadView, attribute: .CenterX, relatedBy: .Equal, toItem: window.contentView, attribute: .CenterX, multiplier: 1.0, constant: -44.0))
        window.contentView?.addConstraint(NSLayoutConstraint(item: dpadView, attribute: .Width, relatedBy: .Equal, toItem: nil, attribute: .NotAnAttribute, multiplier: 1.0, constant: 80.0))
        window.contentView?.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|-(30)-[leftStickView(80)]-(16)-[dpadView(80)]", options: [], metrics: nil, views: views))
        window.contentView?.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|-(30)-[rightStickView(80)]", options: [], metrics: nil, views: views))
        
        server = Server(name: "TestServer", controllerTypes: [.HID])
        server.delegate = self
        server.start()
    }
    
    func server(server: Server, controllerConnected controller: Controller, type: ControllerType) {
        print("Found controller: \(controller.state.name.value)")
        client = Client(name: "Test", controller: controller)
        client?.delegate = self
        client?.start()
        
//        controller.state.leftThumbstick.observe { change in
//            self.leftStickView.state = change.new!
//        }
//        controller.state.rightThumbstick.observe { change in
//            self.rightStickView.state = change.new!
//        }
//        controller.state.dpad.observe { change in
//            self.dpadView.state = change.new
//        }
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
        print(error)
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
        NSColor.greenColor().setStroke()
        let backgroundPath = NSBezierPath(ovalInRect: dirtyRect)
        backgroundPath.lineWidth = 2.0
        backgroundPath.stroke()
        let path = NSBezierPath()
        path.moveToPoint(NSPoint(x: dirtyRect.midX, y: dirtyRect.midY))
        path.lineToPoint(NSPoint(x: CGFloat(state.xAxis) * dirtyRect.midX + dirtyRect.midX, y: CGFloat(state.yAxis) * dirtyRect.midY + dirtyRect.midY))
        path.lineWidth = 2.0
        path.stroke()
    }
}

