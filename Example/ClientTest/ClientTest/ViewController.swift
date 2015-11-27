//
//  ViewController.swift
//  ClientTest
//
//  Created by Robin Goos on 27/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import UIKit
import ControllerKit
import Act

class ViewController: UIViewController, ClientDelegate, ControllerBrowserDelegate {

    var inputHandler: ObservableActor<GamepadState>!
    var controller: Controller!
    var client: Client!
    var server: ControllerBrowser!
    var joystickView: JoystickView!
    var leftStickView: JoystickView!
    var rightStickView: JoystickView!
    var dpadView: JoystickView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        
//        server = ControllerBrowser(name: "TestServer", controllerTypes: [.Remote])
//        server.delegate = self
//        server.start()
        
        inputHandler = ControllerInputHandler(GamepadState(layout: .Micro), processingQueue: NSRunLoop.mainRunLoop())
        controller = Controller(inputHandler: inputHandler)
        
        client = Client(name: "testclient", controllers: [controller])
        client.delegate = self
        
        leftStickView = JoystickView()
        rightStickView = JoystickView()
        dpadView = JoystickView()
        
        leftStickView.translatesAutoresizingMaskIntoConstraints = false
        rightStickView.translatesAutoresizingMaskIntoConstraints = false
        dpadView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(leftStickView)
        view.addSubview(rightStickView)
        view.addSubview(dpadView)
        
        let views = ["leftStickView": leftStickView, "rightStickView": rightStickView, "dpadView": dpadView]
        view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|-(>=30)-[leftStickView(80)]-(16)-[rightStickView(80)]-(>=30)-|", options: [], metrics: nil, views: views))
        view.addConstraint(NSLayoutConstraint(item: leftStickView, attribute: .CenterX, relatedBy: .Equal, toItem: view, attribute: .CenterX, multiplier: 1.0, constant: -44.0))
        view.addConstraint(NSLayoutConstraint(item: dpadView, attribute: .CenterX, relatedBy: .Equal, toItem: view, attribute: .CenterX, multiplier: 1.0, constant: -44.0))
        view.addConstraint(NSLayoutConstraint(item: dpadView, attribute: .Width, relatedBy: .Equal, toItem: nil, attribute: .NotAnAttribute, multiplier: 1.0, constant: 80.0))
        view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|-(30)-[leftStickView(80)]-(16)-[dpadView(80)]", options: [], metrics: nil, views: views))
        view.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|-(30)-[rightStickView(80)]", options: [], metrics: nil, views: views))
        
        client.start()
    }
    
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        sendInput(touches, withEvent: event)
    }
    
    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?) {
        sendInput(touches, withEvent: event)
    }
    
    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        sendInput(touches, withEvent: event)
    }
    
    func sendInput(touches: Set<UITouch>, withEvent event: UIEvent?) {
        let firstTouch = touches.first
        let point = firstTouch!.locationInView(view)
        let relativeX = (point.x - view.center.x) / view.center.x
        let relativeY = (view.center.y - point.y) / view.center.y
        let message = JoystickMessage(joystick: .Dpad, state: JoystickState(xAxis: Float(relativeX), yAxis: Float(relativeY)))
        
        inputHandler.send(message)
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

    }
    
    func controllerBrowser(browser: ControllerBrowser, controllerConnected controller: Controller, type: ControllerType) {
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
        print("Disconnected controller: \(controller.name)")
    }
    
    func controllerBrowser(browser: ControllerBrowser, encounteredError error: NSError) {
        print("Encountered error: \(error)")
    }
}

class JoystickView : UIView {
    var state: JoystickState = JoystickState(xAxis: 0, yAxis: 0) {
        didSet {
            dispatch_async(dispatch_get_main_queue()) {
                self.setNeedsDisplay()
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func linkFired() {
        setNeedsDisplay()
    }
    
    override func drawRect(rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()
        
        CGContextClearRect(ctx, rect)
        CGContextSetLineWidth(ctx, 2.0)
        CGContextSetStrokeColorWithColor(ctx, UIColor.greenColor().CGColor)
        CGContextMoveToPoint(ctx, rect.midX, rect.midY)
        CGContextAddLineToPoint(ctx, CGFloat(state.xAxis) * rect.midX + rect.midX, CGFloat(state.yAxis) * rect.midY + rect.midY)
        CGContextStrokePath(ctx)
    }
}