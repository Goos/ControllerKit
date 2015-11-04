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

class ViewController: UIViewController, ClientDelegate, ServerDelegate {

    var inputHandler: Actor<GamepadState>!
    var client: Client?
    var server: Server!
    var joystickView: JoystickView!
    var controller: Controller?
    var leftStickView: JoystickView!
    var rightStickView: JoystickView!
    var dpadView: JoystickView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        server = Server(name: "TestServer", controllerTypes: [.Remote])
        server.delegate = self
        server.start()
        
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
        
        server = Server(name: "TestServer")
        server.delegate = self
        server.start()
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
//        let firstTouch = touches.first
//        let point = firstTouch!.locationInView(view)
//        let relativeX = (point.x - view.center.x) / view.center.x
//        let relativeY = (view.center.y - point.y) / view.center.y
//        let message = JoystickChanged(joystick: .Dpad, state: JoystickState(xAxis: Float(relativeX), yAxis: Float(relativeY)))
//        
//        controller?.inputHandler.send(message)
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
    
    func server(server: Server, controllerConnected controller: Controller, type: ControllerType) {
        controller.state.leftThumbstick.observe { change in
            self.leftStickView.state = change.new!
        }
        controller.state.rightThumbstick.observe { change in
            self.rightStickView.state = change.new!
        }
        controller.state.dpad.observe { change in
            self.dpadView.state = change.new
        }
        
    }
    
    func server(server: Server, controllerDisconnected controller: Controller) {
        print("Disconnected controller: \(controller.state.name.value)")
    }
    
    func server(server: Server, encounteredError error: ErrorType) {

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