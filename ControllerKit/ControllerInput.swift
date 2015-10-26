//
//  ControllerInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import Act

struct ConnectionChanged : Message {
    let type = "ConnectionChanged"
    let status: ConnectionStatus
}

struct ButtonChanged : Message {
    enum Button {
        case A, B, X, Y, LS, RS
    }
    
    let type = "ButtonChanged"
    let button: Button
    let state: ButtonState
}

struct DpadChanged : Message {
    let type = "DpadChanged"
    let state: DpadState
}

