//
//  NativeControllerAdapter.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import GameController
import Act

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