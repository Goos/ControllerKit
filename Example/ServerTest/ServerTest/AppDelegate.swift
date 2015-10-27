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
class AppDelegate: NSObject, NSApplicationDelegate, ServerDelegate {

    @IBOutlet weak var window: NSWindow!
    var server: Server!

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        server = Server(name: "TestServer")
        server.delegate = self
        server.publish()
        // Insert code here to initialize your application
    }
    
    func server(server: Server, discoveredController controller: Controller) {
        print("Found controller: \(controller)")
        controller.state.dpad.observe { (change) in
            print(change.new.xAxis, change.new.yAxis)
        }
    }
    
    func server(server: Server, disconnectedController controller: Controller) {

    }
    
    func server(server: Server, encounteredError error: NSError) {

    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }


}

