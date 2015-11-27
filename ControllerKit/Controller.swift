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
    case let m as GamepadLayoutMessage:
        if m.layout == state.layout {
            return state
        } else {
            return GamepadState(layout: m.layout)
        }
    case let m as ButtonMessage:
        var s = state
        switch(m.button) {
        case .A: s.buttonA = m.value
        case .B: s.buttonB = m.value
        case .X: s.buttonX = m.value
        case .Y: s.buttonY = m.value
        case .LS: s.leftShoulder = m.value
        case .RS: s.rightShoulder = m.value
        case .LT: s.leftTrigger = m.value
        case .RT: s.rightTrigger = m.value
        case .Pause: break
        }
    case let m as JoystickMessage:
        var s = state
        switch(m.joystick) {
        case .Dpad: s.dpad = m.state
        case .LeftThumbstick: s.leftThumbstick = m.state
        case .RightThumbstick: s.rightThumbstick = m.state
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
    public internal(set) var index: UInt16 = 0
    public internal(set) var name: String?
    public internal(set) var status: ConnectionStatus = .Connected
    internal let inputHandler: ObservableActor<GamepadState>
    private var unobserve: (() -> ())? = nil
    
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
            self.buttonB.value = state.buttonA
            self.buttonX.value = state.buttonA
            self.buttonY.value = state.buttonA
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
    
//    public init(nativeController: GCController, queue: Queueable = dispatch_get_main_queue().queueable()) {
//        var type: GamepadLayout
//        if nativeController.extendedGamepad != nil {
//            type = .Extended
//        } else if nativeController.gamepad != nil {
//            type = .Regular
//        } else {
//            type = .Micro
//        }
//        
//        throttler = ThrottlingTransformer(interval: 1.0 / 60.0)
//        
//        inputHandler = Actor(initialState: GamepadState(type: type), transformers: [throttler!.receive], reducer: GamepadStateReducer, processingQueue: queue)
//        pipe(nativeController, inputHandler)
//    }
}

public func ControllerInputHandler(initialState: GamepadState = GamepadState(layout: .Regular), processingQueue: Queueable? = nil) -> ObservableActor<GamepadState> {
    return ObservableActor(initialState: initialState, transformers: [], reducer: GamepadStateReducer, processingQueue: processingQueue)
}