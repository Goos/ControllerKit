//
//  GameViewController.swift
//  ControllerKitDemo
//
//  Created by Robin Goos on 04/11/15.
//  Copyright (c) 2015 Robin Goos. All rights reserved.
//

import UIKit
import SpriteKit
import ControllerKit

final class Player {
    let node: SKLabelNode
    let nameNode: SKLabelNode
    let controller: Controller
    init(controller: Controller) {
        node = SKLabelNode(text: "😑")
        let name = controller.state.name.value ?? "Controller: \(controller.index)"
        nameNode = SKLabelNode(text: name)
        self.controller = controller
    }
}

class GameViewController: UIViewController, ServerDelegate {
    var server: Server!
    var scene: GameScene!
    var players: [Player] = []
    var displayLink: CADisplayLink!

    override func viewDidLoad() {
        super.viewDidLoad()

        if let scene = GameScene(fileNamed: "GameScene") {
            self.scene = scene
            // Configure the view.
            let skView = self.view as! SKView
            skView.showsFPS = true
            skView.showsNodeCount = true
            
            /* Sprite Kit applies additional optimizations to improve rendering performance */
            skView.ignoresSiblingOrder = true
            
            /* Set the scale mode to scale to fit the window */
            scene.scaleMode = .AspectFill
            
            skView.presentScene(scene)
        }
        
        displayLink = CADisplayLink(target: self, selector: "linkFired")
        displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        
        server = Server(name: "TV-Demo")
        server.delegate = self
        server.start()
    }
    
    func linkFired() {
        for player in players {
            var xPos = player.node.position.x
            var yPos = player.node.position.y
            if let thumbstick = player.controller.state.leftThumbstick.value {
                xPos = player.node.position.x + 10.0 * CGFloat(thumbstick.xAxis)
                yPos = player.node.position.y - 10.0 * CGFloat(thumbstick.yAxis)
            } else {
                let dpad = player.controller.state.dpad.value
                xPos = player.node.position.x + 10.0 * CGFloat(dpad.xAxis)
                yPos = player.node.position.y - 10.0 * CGFloat(dpad.yAxis)
            }
            
            player.node.position = CGPoint(x: xPos, y: yPos)
            player.nameNode.position = CGPoint(x: xPos, y: yPos + 10.0)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    func server(server: Server, controllerConnected controller: Controller, type: ControllerType) {
        print("Connected controller: \(controller.state.name.value)")
        dispatch_async(dispatch_get_main_queue()) {
            let player = Player(controller: controller)
            player.node.position = CGPoint(x: self.view.frame.midX, y: self.view.frame.midY)
            player.nameNode.position = CGPoint(x: self.view.frame.midX, y: self.view.frame.midY)
            self.scene.addChild(player.node)
            self.scene.addChild(player.nameNode)
            self.players.append(player)
        }
        
        controller.state.dpad.observe {
            print($0)
        }
    }
    
    func server(server: Server, controllerDisconnected controller: Controller) {
        print("Disconnected controller: \(controller.state.name.value)")
    }
    
    func server(server: Server, encounteredError error: ErrorType) {

    }
}
