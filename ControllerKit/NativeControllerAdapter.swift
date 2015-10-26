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

func bind(nativeController: GCController, _ inputHandler: Actor<ControllerState>) {
    func buttonAChanged(button: GCControllerButtonInput, value: Float, pressed: Bool) {
        let state = ButtonState(value: value, pressed: pressed)
        inputHandler.send(ButtonChanged(button: .A, state: state))
    }
    
    func buttonBChanged(button: GCControllerButtonInput, value: Float, pressed: Bool) {
        let state = ButtonState(value: value, pressed: pressed)
        inputHandler.send(ButtonChanged(button: .B, state: state))
    }
    
    func buttonXChanged(button: GCControllerButtonInput, value: Float, pressed: Bool) {
        let state = ButtonState(value: value, pressed: pressed)
        inputHandler.send(ButtonChanged(button: .X, state: state))
    }
    
    func buttonYChanged(button: GCControllerButtonInput, value: Float, pressed: Bool) {
        let state = ButtonState(value: value, pressed: pressed)
        inputHandler.send(ButtonChanged(button: .Y, state: state))
    }
    
    func leftShoulderChanged(button: GCControllerButtonInput, value: Float, pressed: Bool) {
        let state = ButtonState(value: value, pressed: pressed)
        inputHandler.send(ButtonChanged(button: .LS, state: state))
    }
    
    func rightShoulderChanged(button: GCControllerButtonInput, value: Float, pressed: Bool) {
        let state = ButtonState(value: value, pressed: pressed)
        inputHandler.send(ButtonChanged(button: .RS, state: state))
    }
    
    func dpadChanged(axis: GCControllerDirectionPad, xAxis: Float, yAxis: Float) {
        let state = DpadState(xAxis: xAxis, yAxis: yAxis)
        inputHandler.send(DpadChanged(state: state))
    }
    
    if let gamepad = nativeController.gamepad {
        gamepad.buttonA.valueChangedHandler = buttonAChanged
        gamepad.buttonB.valueChangedHandler = buttonBChanged
        gamepad.buttonX.valueChangedHandler = buttonXChanged
        gamepad.buttonY.valueChangedHandler = buttonYChanged
        gamepad.leftShoulder.valueChangedHandler = leftShoulderChanged
        gamepad.rightShoulder.valueChangedHandler = rightShoulderChanged
        gamepad.dpad.valueChangedHandler = dpadChanged
    }
    
}