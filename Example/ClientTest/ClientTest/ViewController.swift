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

class ViewController: UIViewController, ClientDelegate {

    var inputHandler: Actor<ControllerState>!
    var client: Client!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        inputHandler = ControllerInputHandler(processingQueue: NSRunLoop.mainRunLoop())
        let controller = Controller(inputHandler: inputHandler)
        client = Client(name: "TestClient", controller: controller)
        client.delegate = self
        client.publish()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        let firstTouch = touches.first
        let point = firstTouch!.locationInView(view)
        let relativeX = (point.x - view.center.x) / view.center.x
        let relativeY = (view.center.y - point.y) / view.center.y
        let message = DpadChanged(state: DpadState(xAxis: Float(relativeX), yAxis: Float(relativeY)))
        inputHandler.send(message)
    }
    
    func client(client: Client, discoveredService service: NSNetService) {
        client.connect(service, success: {
            print("Connected")
        }, error: { error in
            print("Error")
        })
    }
    
    func client(client: Client, lostService service: NSNetService) {
        
    }
    
    func clientLostConnection(client: Client) {

    }
}

