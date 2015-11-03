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

    override func viewDidLoad() {
        super.viewDidLoad()
        
//        let state = GamepadState(type: .Micro)
//        inputHandler = ControllerInputHandler(state, processingQueue: NSRunLoop.mainRunLoop())
//        let controller = Controller(inputHandler: inputHandler)
//        client = Client(name: "TestClient", controller: controller)
//        client.delegate = self
//        client.start()

//        joystickView = JoystickView(frame: self.view.bounds)
//        joystickView.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
//        self.view.addSubview(joystickView)
        server = Server(name: "TestServer", controllerTypes: [.MFi])
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
        print("Found controller: \(controller.state.name.value)")
        self.controller = controller
        
        client = Client(name: "TestController", controller: controller)
        client?.delegate = self
        client?.start()
//        controller.state.dpad.observe { change in
//            self.joystickView.state = change.new
//        }
    }
    
    func server(server: Server, controllerDisconnected controller: Controller) {
        print("Disconnected controller: \(controller.state.name.value)")
    }
    
    func server(server: Server, encounteredError error: ErrorType) {

    }
}

class JoystickView : UIView {
    var state: JoystickState = JoystickState(xAxis: 0, yAxis: 0)
    var displayLink: CADisplayLink!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        displayLink = CADisplayLink(target: self, selector: "linkFired")
        displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
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
        CGContextMoveToPoint(ctx, frame.midX, frame.midY)
        CGContextAddLineToPoint(ctx, CGFloat(state.xAxis) * frame.midX + frame.midX, CGFloat(state.yAxis) * frame.midY + frame.midY)
        CGContextStrokePath(ctx)
        
    }
}