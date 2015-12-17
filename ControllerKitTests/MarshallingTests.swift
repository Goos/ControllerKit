//
//  MarshallingTests.swift
//  ControllerKit
//
//  Created by Robin Goos on 17/12/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import XCTest
@testable import ControllerKit

class MarshallingTests: XCTestCase {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testButtonMarshalling() {
        let message = ButtonMessage(button: .Y, value: 0.5135)
        let marshalled = message.marshal()
        let demarshalled = ButtonMessage(data: marshalled)
        
        XCTAssertNotNil(demarshalled, "The demarshalled button message should not be nil")
        XCTAssertEqual(message.value, demarshalled?.value, "The value of the button message should be equal before and after marshalling")
        XCTAssertEqual(message.button, demarshalled?.button, "The type of the button message should be equal before and after marshalling")
    }
    
    func testFailingButtonMarshalling() {
        var buffer = WriteBuffer()
        buffer << UInt16(100)
        buffer << Float(0.5)
        let message = ButtonMessage(data: buffer.data)
        
        XCTAssertNil(message, "The button message should fail to demarshal due to an unknown button type.")
    }
    
    func testJoystickMarshalling() {
        let message = JoystickMessage(joystick: .RightThumbstick, state: JoystickState(xAxis: 0.315, yAxis: -0.999991))
        let marshalled = message.marshal()
        let demarshalled = JoystickMessage(data: marshalled)
        
        XCTAssertNotNil(demarshalled, "The demarshalled joystick message should not be nil")
        XCTAssertEqual(message.state, demarshalled?.state, "The value of the joystick message should be equal before and after marshalling")
        XCTAssertEqual(message.joystick, demarshalled?.joystick, "The type of the joystick message should be equal before and after marshalling")
    }
    
    func testFailingJoystickMarshalling() {
        var buffer = WriteBuffer()
        buffer << UInt16(5)
        buffer << Float(0.5)
        buffer << Float(-0.5)
        let message = JoystickMessage(data: buffer.data)
        
        XCTAssertNil(message, "The joystick message should fail to demarshal due to an unknown joystick type.")
    }
    
    func testGamepadMarshalling() {
        var state = GamepadState(layout: .Extended)
        state.buttonA = 0.4
        state.buttonX = 0.7
        state.buttonB = 0.31
        state.buttonY = 0.45
        state.leftShoulder = 0.73
        state.rightShoulder = 0.83
        state.leftTrigger = 0.93
        state.rightTrigger = 0.14
        state.dpad = JoystickState(xAxis: 0.41, yAxis: -0.13)
        state.leftThumbstick = JoystickState(xAxis: 0.62, yAxis: -0.01)
        state.rightThumbstick = JoystickState(xAxis: 0.59, yAxis: -0.93)
        
        let message = GamepadMessage(state: state)
        let marshalled = message.marshal()
        let demarshalled = GamepadMessage(data: marshalled)
        
        XCTAssertNotNil(demarshalled, "The demarshalled gamepad message should not be nil")
        XCTAssertEqual(message.state, demarshalled?.state, "The state of the gamepad message should be equal before and after marshalling")
        XCTAssertEqual(message.state.layout, demarshalled?.state.layout, "The layout of the gamepad should be equal before and after marshalling")
    }
}
