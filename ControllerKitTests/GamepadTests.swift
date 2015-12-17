//
//  GamepadTests.swift
//  ControllerKit
//
//  Created by Robin Goos on 17/12/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import XCTest
import Act
@testable import ControllerKit

class GamepadTests: XCTestCase {
    var inputHandler: ObservableActor<GamepadState>!

    override func setUp() {
        super.setUp()
        inputHandler = ObservableActor(initialState: GamepadState(layout: .Extended), transformers: [], reducer: GamepadStateReducer)
    }
    
    override func tearDown() {
        super.tearDown()
        inputHandler = nil
    }
    
    func testButtonMessageHandling() {
        let buttonA = ButtonMessage(button: .A, value: 0.56)
        let buttonX = ButtonMessage(button: .X, value: 0.36)
        let buttonY = ButtonMessage(button: .Y, value: 0.43)
        let buttonB = ButtonMessage(button: .B, value: 0.27)
        let leftShoulder = ButtonMessage(button: .LS, value: 0.11)
        let rightShoulder = ButtonMessage(button: .RS, value: 0.15)
        let leftTrigger = ButtonMessage(button: .LT, value: 0.75)
        let rightTrigger = ButtonMessage(button: .RT, value: 0.89)
        
        let expectation = expectationWithDescription("The gamepad input handler should update the gamepad's buttons in accordance with the messages sent.")
        
        inputHandler.observe { state in
            if state.buttonA == buttonA.value &&
                state.buttonX == buttonX.value &&
                state.buttonY == buttonY.value &&
                state.buttonB == buttonB.value &&
                state.leftShoulder == leftShoulder.value &&
                state.rightShoulder == rightShoulder.value &&
                state.leftTrigger == leftTrigger.value &&
                state.rightTrigger == rightTrigger.value {
                expectation.fulfill()
            }
        }
        
        inputHandler.send(buttonA)
        inputHandler.send(buttonX)
        inputHandler.send(buttonY)
        inputHandler.send(buttonB)
        inputHandler.send(leftShoulder)
        inputHandler.send(rightShoulder)
        inputHandler.send(leftTrigger)
        inputHandler.send(rightTrigger)
        
        waitForExpectationsWithTimeout(1, handler: nil)
    }
    
    func testJoystickMessageHandling() {
        let dpad = JoystickMessage(joystick: .Dpad, state: JoystickState(xAxis: 0.31, yAxis: 0.71))
        let leftThumbstick = JoystickMessage(joystick: .LeftThumbstick, state: JoystickState(xAxis: 0.22, yAxis: 0.91))
        let rightThumbstick = JoystickMessage(joystick: .RightThumbstick, state: JoystickState(xAxis: 0.45, yAxis: 0.11))
        
        let expectation = expectationWithDescription("The gamepad input handler should update the gamepad's joysticks in accordance with the messages sent.")
        
        inputHandler.observe{ state in
            if state.dpad == dpad.state &&
                state.leftThumbstick == leftThumbstick.state &&
                state.rightThumbstick == rightThumbstick.state {
                expectation.fulfill()
            }
        }
        
        inputHandler.send(dpad)
        inputHandler.send(leftThumbstick)
        inputHandler.send(rightThumbstick)
        
        waitForExpectationsWithTimeout(1, handler: nil)
    }
    
    func testInputBounding() {
        let unreasonableButtonMessage = ButtonMessage(button: .A, value: 1000.0)
        let unreasonableJoystickMessage = JoystickMessage(joystick: .Dpad, state: JoystickState(xAxis: -500.0, yAxis: 31000.0))
        
        let expectation = expectationWithDescription("The gamepad input handler should bound the values of incoming messages when reducing them down to the state.")
        
        inputHandler.observe { state in
            if state.buttonA == 1.0 &&
                state.dpad.xAxis == -1.0 &&
                state.dpad.yAxis == 1.0 {
                expectation.fulfill()
            }
        }
        
        inputHandler.send(unreasonableButtonMessage)
        inputHandler.send(unreasonableJoystickMessage)
        
        waitForExpectationsWithTimeout(1, handler: nil)
    }
}