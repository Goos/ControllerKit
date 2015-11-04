//
//  ControllerInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import Act

public struct ConnectionChanged : Message {
    public let type = "ConnectionChanged"
    public let status: ConnectionStatus
    
    public init(status: ConnectionStatus) {
        self.status = status
    }
}

public struct SetGamepadType : Message {
    public let type = "SetGamepadType"
    public let gamepad: GamepadType
    
    public init(type: GamepadType) {
        gamepad = type
    }
}

public struct SetControllerName : Message {
    public let type = "SetControllerName"
    public let name: String?
    
    public init(name: String?) {
        self.name = name
    }
}

public struct ButtonChanged : Message {
    public let type = "ButtonChanged"
    public let button: ButtonType
    public let state: ButtonState?
    
    public init(button: ButtonType, state: ButtonState?) {
        self.button = button
        self.state = state
    }
}

public struct JoystickChanged : Message {
    public let type = "JoystickChanged"
    public let joystick: JoystickType
    public let state: JoystickState?
    
    public init(joystick: JoystickType, state: JoystickState?) {
        self.joystick = joystick
        self.state = state
    }
}