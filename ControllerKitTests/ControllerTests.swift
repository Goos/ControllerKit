//
//  ControllerTests.swift
//  ControllerKit
//
//  Created by Robin Goos on 17/12/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import XCTest
import Act
@testable import ControllerKit

class ControllerTests: XCTestCase {
    var inputHandler: ObservableActor<GamepadState>!
    var controller: Controller!

    override func setUp() {
        super.setUp()
        inputHandler = ObservableActor(initialState: GamepadState(layout: .Extended), transformers: [], reducer: GamepadStateReducer)
        controller = Controller(inputHandler: inputHandler)
    }
    
    override func tearDown() {
        super.tearDown()
        inputHandler = nil
        controller = nil
    }
    
    private func addButtonHandlerWithExpectation(message: ButtonMessage, button: ButtonInput) {
        let expectation = expectationWithDescription("The controller handler for button \(message.button) should be triggered once it handles a message for it.")
        button.valueChangedHandler = { (value, pressed) in
            if message.value == value {
                expectation.fulfill()
            }
        }
    }

    func testButtonHandlers() {
        let buttonA = ButtonMessage(button: .A, value: 0.56)
        let buttonX = ButtonMessage(button: .X, value: 0.36)
        let buttonY = ButtonMessage(button: .Y, value: 0.43)
        let buttonB = ButtonMessage(button: .B, value: 0.27)
        let leftShoulder = ButtonMessage(button: .LS, value: 0.11)
        let rightShoulder = ButtonMessage(button: .RS, value: 0.15)
        let leftTrigger = ButtonMessage(button: .LT, value: 0.75)
        let rightTrigger = ButtonMessage(button: .RT, value: 0.89)
        
        addButtonHandlerWithExpectation(buttonA, button: controller.buttonA)
        addButtonHandlerWithExpectation(buttonX, button: controller.buttonX)
        addButtonHandlerWithExpectation(buttonY, button: controller.buttonY)
        addButtonHandlerWithExpectation(buttonB, button: controller.buttonB)
        addButtonHandlerWithExpectation(leftShoulder, button: controller.leftShoulder)
        addButtonHandlerWithExpectation(rightShoulder, button: controller.rightShoulder)
        addButtonHandlerWithExpectation(leftTrigger, button: controller.leftTrigger)
        addButtonHandlerWithExpectation(rightTrigger, button: controller.rightTrigger)
        
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
    
    private func addJoystickHandlerWithExpectation(message: JoystickMessage, joystick: JoystickInput) {
        let expectation = expectationWithDescription("The controller handler for joystick \(message.joystick) should be triggered once it handles a message for it.")
        joystick.valueChangedHandler = { (xAxis, yAxis) in
            if message.state.xAxis == xAxis && message.state.yAxis == yAxis {
                expectation.fulfill()
            }
        }
    }
    
    func testJoystickHandlers() {
        let dpad = JoystickMessage(joystick: .Dpad, state: JoystickState(xAxis: 0.31, yAxis: 0.71))
        let leftThumbstick = JoystickMessage(joystick: .LeftThumbstick, state: JoystickState(xAxis: 0.22, yAxis: 0.91))
        let rightThumbstick = JoystickMessage(joystick: .RightThumbstick, state: JoystickState(xAxis: 0.45, yAxis: 0.11))
        
        addJoystickHandlerWithExpectation(dpad, joystick: controller.dpad)
        addJoystickHandlerWithExpectation(leftThumbstick, joystick: controller.leftThumbstick)
        addJoystickHandlerWithExpectation(rightThumbstick, joystick: controller.rightThumbstick)
        
        inputHandler.send(dpad)
        inputHandler.send(leftThumbstick)
        inputHandler.send(rightThumbstick)
        
        waitForExpectationsWithTimeout(1, handler: nil)
    }
    
    func testNameChangeHandler() {
        let expectation = expectationWithDescription("The name change handler should be triggered if the controller's name is changed.")
        let newName = "fancy new name"
        
        controller.nameChangedHandler = { name in
            if name == newName {
                expectation.fulfill()
            }
        }
        
        controller.name = newName
        waitForExpectationsWithTimeout(1, handler: nil)
    }
}
