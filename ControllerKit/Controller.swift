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

public enum ConnectionStatus : Int {
    case Disconnected
    case Connecting
    case Connected
}

public enum ButtonType : UInt16 {
    case A = 1
    case B = 2
    case X = 3
    case Y = 4
    case LS = 5
    case RS = 6
    case LT = 7
    case RT = 8
    case Pause = 9
}

public struct ButtonState {
    public let value: Float
    public let pressed: Bool
    
    public init(value: Float, pressed: Bool) {
        self.value = value
        self.pressed = pressed
    }
}

public func ==(lhs: ButtonState, rhs: ButtonState) -> Bool {
    return lhs.value == rhs.value
}

public enum JoystickType : UInt16 {
    case Dpad = 1
    case LeftThumbstick = 2
    case RightThumbstick = 3
}

public struct JoystickState {
    public let xAxis: Float
    public let yAxis: Float
    
    public var up: Bool {
        return yAxis < 0.0
    }
    
    public var right: Bool {
        return xAxis > 0.0
    }
    
    public var down: Bool {
        return yAxis > 0.0
    }
    
    public var left: Bool {
        return xAxis < 0.0
    }
    
    public init(xAxis: Float, yAxis: Float) {
        self.xAxis = xAxis
        self.yAxis = yAxis
    }
}

public func ==(lhs: JoystickState, rhs: JoystickState) -> Bool {
    return lhs.xAxis == rhs.xAxis && lhs.yAxis == rhs.yAxis
}

public enum GamepadType : UInt16 {
    case Micro = 1
    case Regular = 2
    case Extended = 3
}

public final class GamepadState {
    var status: ConnectionStatus
    public internal(set) var type: GamepadType
    public let name: Observable<String?>
    
    public let buttonA: Observable<ButtonState>
    public let buttonB: Observable<ButtonState?>
    public let buttonX: Observable<ButtonState>
    public let buttonY: Observable<ButtonState?>
    
    public let leftShoulder: Observable<ButtonState?>
    public let rightShoulder: Observable<ButtonState?>
    public let leftTrigger: Observable<ButtonState?>
    public let rightTrigger: Observable<ButtonState?>
    
    public let dpad: Observable<JoystickState>
    
    public internal(set) var leftThumbstick: Observable<JoystickState?>
    public internal(set) var rightThumbstick: Observable<JoystickState?>
    
    public init(type: GamepadType) {
        self.type = type
        status = .Connected
        name = Observable("")
        
        buttonA = Observable(ButtonState(value: 0, pressed: false))
        buttonX = Observable(ButtonState(value: 0, pressed: false))
        
        dpad = Observable(JoystickState(xAxis: 0, yAxis: 0))
        
        if (type == .Regular || type == .Extended) {
            buttonB = Observable(ButtonState(value: 0, pressed: false))
            buttonY = Observable(ButtonState(value: 0, pressed: false))
            leftShoulder = Observable(ButtonState(value: 0, pressed: false))
            rightShoulder = Observable(ButtonState(value: 0, pressed: false))
        } else {
            buttonB = Observable(nil)
            buttonY = Observable(nil)
            leftShoulder = Observable(nil)
            rightShoulder = Observable(nil)
        }
        
        if (type == .Extended) {
            leftTrigger = Observable(ButtonState(value: 0, pressed: false))
            rightTrigger = Observable(ButtonState(value: 0, pressed: false))
            leftThumbstick = Observable(JoystickState(xAxis: 0, yAxis: 0))
            rightThumbstick = Observable(JoystickState(xAxis: 0, yAxis: 0))
        } else {
            leftTrigger = Observable(nil)
            rightTrigger = Observable(nil)
            leftThumbstick = Observable(nil)
            rightThumbstick = Observable(nil)
        }
    }
}

public func GamepadStateReducer(state: GamepadState, message: Message) -> GamepadState {
    switch(message) {
    case let m as ConnectionChanged:
        state.status = m.status
    case let m as SetGamepadType:
        if m.controllerType == state.type { break }
        if state.type == .Micro && m.controllerType == .Regular {
            state.buttonB.value = ButtonState(value: 0, pressed: false)
            state.buttonY.value = ButtonState(value: 0, pressed: false)
            state.leftShoulder.value = ButtonState(value: 0, pressed: false)
            state.rightShoulder.value = ButtonState(value: 0, pressed: false)
        } else if m.controllerType == .Extended {
            state.leftTrigger.value = ButtonState(value: 0, pressed: false)
            state.rightTrigger.value = ButtonState(value: 0, pressed: false)
            state.leftThumbstick.value = JoystickState(xAxis: 0, yAxis: 0)
            state.rightThumbstick.value = JoystickState(xAxis: 0, yAxis: 0)
        } else if m.controllerType == .Micro {
            state.buttonB.value = nil
            state.buttonY.value = nil
            state.leftShoulder.value = nil
            state.rightShoulder.value = nil
            state.leftTrigger.value = nil
            state.rightTrigger.value = nil
            state.leftThumbstick.value = nil
            state.rightThumbstick.value = nil
        } else if m.controllerType == .Regular {
            state.leftTrigger.value = nil
            state.rightTrigger.value = nil
            state.leftThumbstick.value = nil
            state.rightThumbstick.value = nil
        }
        state.type = m.controllerType
    case let m as ButtonChanged:
        switch(m.button) {
        case .A: if let s = m.state { state.buttonA.value = s }
        case .B: state.buttonB.value = m.state
        case .X: if let s = m.state { state.buttonX.value = s }
        case .Y: state.buttonY.value = m.state
        case .LS: state.leftShoulder.value = m.state
        case .RS: state.rightShoulder.value = m.state
        case .LT: state.leftTrigger.value = m.state
        case .RT: state.rightTrigger.value = m.state
        case .Pause: break
        }
    case let m as JoystickChanged:
        switch(m.joystick) {
        case .Dpad: if let s = m.state { state.dpad.value = s }
        case .LeftThumbstick: state.leftThumbstick.value = m.state
        case .RightThumbstick: state.rightThumbstick.value = m.state
        }
    default:
        break
    }
    
    return state
}

public final class Controller : NSObject {
    internal let inputHandler: Actor<GamepadState>
    public var state: GamepadState {
        return inputHandler.state
    }
    
    public init(nativeController: GCController, queue: Queueable = dispatch_get_main_queue().queueable()) {
        let type: GamepadType = (nativeController.extendedGamepad != nil) ? .Extended : .Regular
        inputHandler = Actor(initialState: GamepadState(type: type), transformers: [], reducer: GamepadStateReducer, processingQueue: queue)
        pipe(nativeController, inputHandler)
    }
    
    public init(inputHandler: Actor<GamepadState>) {
        self.inputHandler = inputHandler
    }
}

public func ControllerInputHandler(initialState: GamepadState = GamepadState(type: .Regular), processingQueue: Queueable? = nil) -> Actor<GamepadState> {
    return Actor(initialState: initialState, transformers: [], reducer: GamepadStateReducer, processingQueue: processingQueue)
}