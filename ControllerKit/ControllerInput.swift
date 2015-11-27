//
//  ControllerInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import Act

public struct GamepadLayoutMessage : Message {
    public let type = "GamepadLayoutMessage"
    public let layout: GamepadLayout
    
    public init(layout: GamepadLayout) {
        self.layout = layout
    }
}

public struct ControllerNameMessage : Message {
    public let type = "ControllerNameMessage"
    public let name: String?
    
    public init(name: String?) {
        self.name = name
    }
}

public struct ButtonMessage : Message {
    public let type = "ButtonMessage"
    public let button: ButtonType
    public let value: Float
    
    public init(button: ButtonType, value: Float) {
        self.button = button
        self.value = value
    }
}

public struct JoystickMessage : Message {
    public let type = "JoystickMessage"
    public let joystick: JoystickType
    public let state: JoystickState
    
    public init(joystick: JoystickType, state: JoystickState) {
        self.joystick = joystick
        self.state = state
    }
}

public struct GamepadMessage : Message {
    public let type = "GamepadMessage"
    public let state: GamepadState
    
    public init(state: GamepadState) {
        self.state = state
    }
}