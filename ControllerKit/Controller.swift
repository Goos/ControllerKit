//
//  Controller.swift
//  ControllerKit
//
//  Created by Robin Goos on 25/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import GameController
import Act

@objc public enum ConnectionStatus : Int {
    case Disconnected
    case Connecting
    case Connected
}

public func GamepadStateReducer(state: GamepadState, message: Message) -> GamepadState {
    switch(message) {
    case let m as ButtonMessage:
        let value = max(0.0, min(m.value, 1.0))
        var s = state
        switch(m.button) {
        case .A: s.buttonA = value
        case .B: s.buttonB = value
        case .X: s.buttonX = value
        case .Y: s.buttonY = value
        case .LS: s.leftShoulder = value
        case .RS: s.rightShoulder = value
        case .LT: s.leftTrigger = value
        case .RT: s.rightTrigger = value
        case .Pause: break
        }
        return s
    case let m as JoystickMessage:
        let x = max(-1.0, min(m.state.xAxis, 1.0))
        let y = max(-1.0, min(m.state.yAxis, 1.0))
        let js = JoystickState(xAxis: x, yAxis: y)
        var s = state
        switch(m.joystick) {
        case .Dpad: s.dpad = js
        case .LeftThumbstick: s.leftThumbstick = js
        case .RightThumbstick: s.rightThumbstick = js
        }
        return s
    case let m as GamepadMessage:
        return m.state
    default:
        break
    }
    
    return state
}

public typealias ButtonInputValueChangedHandler = (Float, Bool) -> Void

public typealias JoystickInputValueChangedHandler = (Float, Float) -> Void

public final class ButtonInput : NSObject {
    public var valueChangedHandler: ButtonInputValueChangedHandler?
    public private(set) var value: Float = 0.0 {
        didSet {
            if oldValue != value {
                valueChangedHandler?(value, pressed)
            }
        }
    }
    public var pressed: Bool {
        return fabs(value - 1.0) < FLT_EPSILON
    }
}

public final class JoystickInput : NSObject {
    public var valueChangedHandler: JoystickInputValueChangedHandler?
    public private(set) var xAxis: Float = 0.0
    public private(set) var yAxis: Float = 0.0
    
    internal func setAxes(xAxis: Float, yAxis: Float) {
        if (self.xAxis != xAxis || self.yAxis != yAxis) {
            valueChangedHandler?(xAxis, yAxis)
        }
        self.xAxis = xAxis
        self.yAxis = yAxis
    }
}

public final class Controller : NSObject {
    internal let inputHandler: ObservableActor<GamepadState>
    private var unobserve: (() -> ())? = nil
    
    public internal(set) var index: UInt16 = 0
    
    public internal(set) var name: String? {
        didSet {
            if oldValue != name {
                nameChangedHandler?(name)
            }
        }
    }
    public var nameChangedHandler: ((String?) -> ())?
    
    public internal(set) var status: ConnectionStatus = .Connected {
        didSet {
            if oldValue != status {
                statusChangedHandler?(status)
            }
        }
    }
    public var statusChangedHandler: ((ConnectionStatus) -> ())?
    
    public var layout: GamepadLayout = .Regular
    
    public let dpad = JoystickInput()
    
    public let buttonA = ButtonInput()
    public let buttonB = ButtonInput()
    public let buttonX = ButtonInput()
    public let buttonY = ButtonInput()
    
    public let leftThumbstick = JoystickInput()
    public let rightThumbstick = JoystickInput()
    
    public let leftShoulder = ButtonInput()
    public let rightShoulder = ButtonInput()
    public let leftTrigger = ButtonInput()
    public let rightTrigger = ButtonInput()
    
    public init(inputHandler: ObservableActor<GamepadState>) {
        self.inputHandler = inputHandler
        super.init()
        unobserve = inputHandler.observe { state in
            self.layout = state.layout
            self.dpad.setAxes(state.dpad.xAxis, yAxis: state.dpad.yAxis)
            self.buttonA.value = state.buttonA
            self.buttonB.value = state.buttonB
            self.buttonX.value = state.buttonX
            self.buttonY.value = state.buttonY
            self.leftThumbstick.setAxes(state.leftThumbstick.xAxis, yAxis: state.leftThumbstick.yAxis)
            self.rightThumbstick.setAxes(state.rightThumbstick.xAxis, yAxis: state.rightThumbstick.yAxis)
            self.leftShoulder.value = state.leftShoulder
            self.rightShoulder.value = state.rightShoulder
            self.leftTrigger.value = state.leftTrigger
            self.rightTrigger.value = state.rightTrigger
        }
    }
    
    deinit {
        unobserve?()
    }
}

public func ControllerInputHandler(initialState: GamepadState = GamepadState(layout: .Regular), processingQueue: Queueable? = nil) -> ObservableActor<GamepadState> {
    return ObservableActor(initialState: initialState, transformers: [], reducer: GamepadStateReducer, messageQueue: processingQueue)
}