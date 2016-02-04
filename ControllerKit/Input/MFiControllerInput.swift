//
//  MFiControllerInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import GameController
import Act

final class MFiControllerSource : NSObject, ControllerSource {
    private var controllers: [GCControllerPlayerIndex:Controller] = [:]
    private var onControllerConnected: ((Controller) -> ())? = nil
    private var onControllerDisconnected: ((Controller) -> ())? = nil
    private var queue: Queueable
    
    init(queue: Queueable) {
        self.queue = queue
        super.init()
    }
    
    deinit {
        stop()
    }
    
    func listen(controllerConnected: (Controller) -> (), controllerDisconnected: (Controller) -> (), error: (NSError) -> ()) {
        onControllerConnected = controllerConnected
        onControllerDisconnected = controllerDisconnected
        
        GCController.startWirelessControllerDiscoveryWithCompletionHandler(nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "controllerDidConnect:", name: GCControllerDidConnectNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "controllerDidDisconnect:", name: GCControllerDidDisconnectNotification, object: nil)
    }
    
    func stop() {
        GCController.stopWirelessControllerDiscovery()
        NSNotificationCenter.defaultCenter().removeObserver(self, name: GCControllerDidConnectNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: GCControllerDidDisconnectNotification, object: nil)
    }
    
    
    func controllerDidConnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController {
            if let existing = controllers[nativeController.playerIndex] {
                existing.status = .Connected
            } else {
                let controller = controllerForNativeController(nativeController)
                controller.index = UInt16(controllers.count)
                controllers[nativeController.playerIndex] = controller
                
                onControllerConnected?(controller)
            }
        }
    }
    
    func controllerDidDisconnect(notification: NSNotification) {
        if let nativeController = notification.object as? GCController, controller = controllers[nativeController.playerIndex] {
            controller.status = .Disconnected
            
            NSTimer.setTimeout(12) { [weak self] in
                if controller.status == .Disconnected {
                    self?.onControllerDisconnected?(controller)
                    self?.controllers.removeValueForKey(nativeController.playerIndex)
                }
            }
        }
    }
    
    func controllerForNativeController(controller: GCController) -> Controller {
        var layout: GamepadLayout
        if controller.extendedGamepad != nil {
            layout = .Extended
        } else if controller.gamepad != nil {
            layout = .Regular
        } else {
            layout = .Micro
        }
        let gamepad = GamepadState(layout: layout)
        let inputHandler = ObservableActor(initialState: gamepad, transformers: [], reducer: GamepadStateReducer, messageQueue: queue)
        pipe(controller, inputHandler)
        return Controller(inputHandler: inputHandler)
    }
}

func pipe(nativeController: GCController, _ inputHandler: Actor<GamepadState>) {
    func buttonChanged(buttonType: ButtonType, value: Float, pressed: Bool) {
        inputHandler.send(ButtonMessage(button: buttonType, value: value))
    }
    
    func joystickChanged(joystick: JoystickType, xAxis: Float, yAxis: Float) {
        let state = JoystickState(xAxis: xAxis, yAxis: yAxis)
        inputHandler.send(JoystickMessage(joystick: joystick, state: state))
    }
    
    if let gamepad = nativeController.extendedGamepad {
        gamepad.buttonA.valueChangedHandler = { buttonChanged(.A, value: $1, pressed: $2) }
        gamepad.buttonB.valueChangedHandler = { buttonChanged(.B, value: $1, pressed: $2) }
        gamepad.buttonX.valueChangedHandler = { buttonChanged(.X, value: $1, pressed: $2) }
        gamepad.buttonY.valueChangedHandler = { buttonChanged(.Y, value: $1, pressed: $2) }
        
        gamepad.leftShoulder.valueChangedHandler = { buttonChanged(.LS, value: $1, pressed: $2) }
        gamepad.rightShoulder.valueChangedHandler = { buttonChanged(.RS, value: $1, pressed: $2) }
        gamepad.leftTrigger.valueChangedHandler = { buttonChanged(.LT, value: $1, pressed: $2) }
        gamepad.rightTrigger.valueChangedHandler = { buttonChanged(.RT, value: $1, pressed: $2) }
        
        gamepad.dpad.valueChangedHandler = { joystickChanged(.Dpad, xAxis: $1, yAxis: $2) }
        gamepad.leftThumbstick.valueChangedHandler = { joystickChanged(.LeftThumbstick, xAxis: $1, yAxis: $2) }
        gamepad.rightThumbstick.valueChangedHandler = { joystickChanged(.RightThumbstick, xAxis: $1, yAxis: $2) }
    } else if let gamepad = nativeController.gamepad {
        gamepad.buttonA.valueChangedHandler = { buttonChanged(.A, value: $1, pressed: $2) }
        gamepad.buttonB.valueChangedHandler = { buttonChanged(.B, value: $1, pressed: $2) }
        gamepad.buttonX.valueChangedHandler = { buttonChanged(.X, value: $1, pressed: $2) }
        gamepad.buttonY.valueChangedHandler = { buttonChanged(.Y, value: $1, pressed: $2) }
        
        gamepad.leftShoulder.valueChangedHandler = { buttonChanged(.LS, value: $1, pressed: $2) }
        gamepad.rightShoulder.valueChangedHandler = { buttonChanged(.RS, value: $1, pressed: $2) }
        
        gamepad.dpad.valueChangedHandler = { joystickChanged(.Dpad, xAxis: $1, yAxis: $2) }
    } else {
    #if os(tvOS)
        if let gamepad = nativeController.microGamepad {
            gamepad.buttonA.valueChangedHandler = { buttonChanged(.A, value: $1, pressed: $2) }
            gamepad.buttonX.valueChangedHandler = { buttonChanged(.X, value: $1, pressed: $2) }
            gamepad.dpad.valueChangedHandler = { joystickChanged(.Dpad, xAxis: $1, yAxis: $2) }
        }
    #endif
    }
}