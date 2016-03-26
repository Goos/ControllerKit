//
//  Gamepad.swift
//  ControllerKit
//
//  Created by Robin Goos on 25/11/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

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

public enum JoystickType : UInt16 {
    case Dpad = 1
    case LeftThumbstick = 2
    case RightThumbstick = 3
}

public struct JoystickState : Equatable {
    public var xAxis: Float
    public var yAxis: Float
    
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

public struct AccelerationState : Equatable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public func ==(lhs: JoystickState, rhs: JoystickState) -> Bool {
    return lhs.xAxis == rhs.xAxis && lhs.yAxis == rhs.yAxis
}

public enum GamepadLayout : UInt16 {
    case Micro = 1
    case Regular = 2
    case Extended = 3
}

typealias Joystick = (xAxis: Float, yAxis: Float)

public struct GamepadState : Equatable {
    public var layout: GamepadLayout
    
    public var buttonA: Float = 0.0
    public var buttonB: Float = 0.0
    public var buttonX: Float = 0.0
    public var buttonY: Float = 0.0
    
    public var leftShoulder: Float = 0.0
    public var rightShoulder: Float = 0.0
    public var leftTrigger: Float = 0.0
    public var rightTrigger: Float = 0.0
    
    public var dpad: JoystickState = JoystickState(xAxis: 0.0, yAxis: 0.0)
    
    public var leftThumbstick: JoystickState = JoystickState(xAxis: 0.0, yAxis: 0.0)
    public var rightThumbstick: JoystickState = JoystickState(xAxis: 0.0, yAxis: 0.0)
    
    public init(layout: GamepadLayout) {
        self.layout = layout
    }
}

public func ==(lhs: GamepadState, rhs: GamepadState) -> Bool {
    return (
        lhs.buttonA == rhs.buttonA &&
        lhs.buttonB == rhs.buttonB &&
        lhs.buttonY == rhs.buttonY &&
        lhs.buttonX == rhs.buttonX &&
        lhs.dpad == rhs.dpad &&
        lhs.leftShoulder == rhs.leftShoulder &&
        lhs.rightShoulder == rhs.rightShoulder &&
        lhs.leftTrigger == rhs.leftTrigger &&
        lhs.rightTrigger == rhs.rightTrigger &&
        lhs.leftThumbstick == rhs.leftThumbstick &&
        lhs.rightThumbstick == rhs.rightThumbstick
    )
}