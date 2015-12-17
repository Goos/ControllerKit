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
class AppDelegate: NSObject, NSApplicationDelegate, ControllerPublisherDelegate, ControllerBrowserDelegate {

    @IBOutlet weak var window: NSWindow!
    var leftStickView: JoystickView!
    var rightStickView: JoystickView!
    var dpadView: JoystickView!
    var buttonAView: NSView!
    var buttonXView: NSView!
    var browser: ControllerBrowser!
    var controller: Controller!
    var publisher: ControllerPublisher!

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        leftStickView = JoystickView()
        rightStickView = JoystickView()
        dpadView = JoystickView()
        
        leftStickView.translatesAutoresizingMaskIntoConstraints = false
        rightStickView.translatesAutoresizingMaskIntoConstraints = false
        dpadView.translatesAutoresizingMaskIntoConstraints = false
        
        buttonAView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        buttonXView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        buttonAView.wantsLayer = true
        buttonXView.wantsLayer = true
        buttonAView.layer = CALayer()
        buttonXView.layer = CALayer()
        buttonAView.translatesAutoresizingMaskIntoConstraints = false
        buttonXView.translatesAutoresizingMaskIntoConstraints = false
        
        window.contentView?.addSubview(leftStickView)
        window.contentView?.addSubview(rightStickView)
        window.contentView?.addSubview(dpadView)
        window.contentView?.addSubview(buttonAView)
        window.contentView?.addSubview(buttonXView)
        
        let views = [
            "leftStickView": leftStickView,
            "rightStickView": rightStickView,
            "dpadView": dpadView,
            "aView": buttonAView,
            "xView": buttonXView,
        ]
        window.contentView?.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|-(>=30)-[leftStickView(80)]-(16)-[rightStickView(80)]-(>=30)-|", options: [], metrics: nil, views: views))
        window.contentView?.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:[aView(40)]-(30)-|", options: [], metrics: nil, views: views))
        window.contentView?.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:[xView(40)]-(30)-|", options: [], metrics: nil, views: views))
        window.contentView?.addConstraint(NSLayoutConstraint(item: leftStickView, attribute: .CenterX, relatedBy: .Equal, toItem: window.contentView, attribute: .CenterX, multiplier: 1.0, constant: -44.0))
        window.contentView?.addConstraint(NSLayoutConstraint(item: dpadView, attribute: .CenterX, relatedBy: .Equal, toItem: window.contentView, attribute: .CenterX, multiplier: 1.0, constant: -44.0))
        window.contentView?.addConstraint(NSLayoutConstraint(item: dpadView, attribute: .Width, relatedBy: .Equal, toItem: nil, attribute: .NotAnAttribute, multiplier: 1.0, constant: 80.0))
        window.contentView?.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|-(30)-[leftStickView(80)]-(16)-[dpadView(80)]", options: [], metrics: nil, views: views))
        window.contentView?.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|-(30)-[rightStickView(80)]", options: [], metrics: nil, views: views))
        window.contentView?.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|-(30)-[aView(40)]-(15)-[xView(40)]", options: [], metrics: nil, views: views))
        
        browser = ControllerBrowser(name: "TestServer")
        browser.delegate = self
        browser.start()
        
//        publisher = ControllerPublisher(name: "Macbook", controllers: [])
//        publisher.delegate = self
//        publisher.start()
    }
    
    func controllerBrowser(browser: ControllerBrowser, controllerConnected controller: Controller) {
        print("found controller: \(controller)")
//        publisher.addController(controller)
        
        controller.leftThumbstick.valueChangedHandler = { (xAxis, yAxis) in
            self.leftStickView.state = JoystickState(xAxis: xAxis, yAxis: yAxis)
        }
        
        controller.rightThumbstick.valueChangedHandler = { (xAxis, yAxis) in
            self.rightStickView.state = JoystickState(xAxis: xAxis, yAxis: yAxis)
        }
        
        controller.dpad.valueChangedHandler = { (xAxis, yAxis) in
            self.dpadView.state = JoystickState(xAxis: xAxis, yAxis: yAxis)
        }
        
        controller.buttonA.valueChangedHandler = { (value, pressed) in
            if pressed {
                self.buttonAView.layer?.backgroundColor = NSColor.greenColor().CGColor
                NSTimer.setTimeout(0.3) {
                    self.buttonAView.layer?.backgroundColor = NSColor.clearColor().CGColor
                }
            }
        }
        
        controller.buttonX.valueChangedHandler = { (value, pressed) in
            if pressed {
                self.buttonXView.layer?.backgroundColor = NSColor.greenColor().CGColor
                NSTimer.setTimeout(0.3) {
                    self.buttonXView.layer?.backgroundColor = NSColor.clearColor().CGColor
                }
            }
        }
    }
    
    func controllerBrowser(browser: ControllerBrowser, controllerDisconnected controller: Controller) {
        print("Disconnected controller: \(controller)")
//        publisher.removeController(controller)
    }
    
    func controllerBrowser(browser: ControllerBrowser, encounteredError error: NSError) {
        print("Encountered error: \(error)")
    }
    
    func publisher(client: ControllerPublisher, discoveredService service: NSNetService) {
        print("Found service: \(service)")
        publisher.connect(service)
    }
    
    func publisher(client: ControllerPublisher, lostService service: NSNetService) {
        
    }
    
    func publisher(client: ControllerPublisher, connectedToService service: NSNetService) {
        print("Connected to: \(service.name)")
    }
    
    func publisher(client: ControllerPublisher, disconnectedFromService service: NSNetService) {
    
    }
    
    func publisher(client: ControllerPublisher, encounteredError error: NSError) {
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

