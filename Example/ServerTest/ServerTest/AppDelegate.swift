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
class AppDelegate: NSObject, NSApplicationDelegate, ClientDelegate, ControllerBrowserDelegate {

    @IBOutlet weak var window: NSWindow!
    var leftStickView: JoystickView!
    var rightStickView: JoystickView!
    var dpadView: JoystickView!
    var browser: ControllerBrowser!
    var controller: Controller!
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
        
        browser = ControllerBrowser(name: "TestServer", controllerTypes: [.Remote, .HID])
        browser.delegate = self
        browser.start()
    }
    
    func controllerBrowser(browser: ControllerBrowser, controllerConnected controller: Controller, type: ControllerType) {
        print("found controller: \(controller)")
        controller.leftThumbstick.valueChangedHandler = { (xAxis, yAxis) in
            self.leftStickView.state = JoystickState(xAxis: xAxis, yAxis: yAxis)
        }
        
        controller.rightThumbstick.valueChangedHandler = { (xAxis, yAxis) in
            self.rightStickView.state = JoystickState(xAxis: xAxis, yAxis: yAxis)
        }
        
        controller.dpad.valueChangedHandler = { (xAxis, yAxis) in
            self.dpadView.state = JoystickState(xAxis: xAxis, yAxis: yAxis)
        }
        
    }
    
    func controllerBrowser(browser: ControllerBrowser, controllerDisconnected controller: Controller) {
        print("Disconnected controller: \(controller)")
    }
    
    func controllerBrowser(browser: ControllerBrowser, encounteredError error: NSError) {
        print("Encountered error: \(error)")
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
    
    func client(client: Client, encounteredError error: NSError) {
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

