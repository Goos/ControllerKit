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
}

public enum ButtonType : Int32 {
    case A = 1
    case B = 2
    case X = 3
    case Y = 4
    case LS = 5
    case RS = 6
}

public final class ButtonChanged : NSObject, NSCoding, Message {
    public let type = "ButtonChanged"
    public let button: ButtonType
    public let state: ButtonState
    
    override init() {
        self.button = .A
        self.state = ButtonState(value: 0.0, pressed: false)
        super.init()
    }
    
    public init(button: ButtonType, state: ButtonState) {
        self.button = button
        self.state = state
        super.init()
    }
    
    public convenience init?(coder aDecoder: NSCoder) {
        let rawButton = aDecoder.decodeInt32ForKey("button")
        guard let
            button = ButtonType(rawValue: rawButton)
        else {
            self.init()
            return nil
        }
        
        let value = aDecoder.decodeFloatForKey("value")
        let pressed = aDecoder.decodeBoolForKey("pressed")
        self.init(button: button, state: ButtonState(value: value, pressed: pressed))
    }
    
    public func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeInt32(button.rawValue, forKey: "button")
        aCoder.encodeFloat(state.value, forKey: "value")
        aCoder.encodeBool(state.pressed, forKey: "pressed")
    }
}

public final class DpadChanged : NSObject, NSCoding, Message {
    public let type = "DpadChanged"
    public let state: DpadState
    
    override init() {
        state = DpadState(xAxis: 0.0, yAxis: 0.0)
        super.init()
    }
    
    public init(state: DpadState) {
        self.state = state
        super.init()
    }
    
    public convenience init?(coder aDecoder: NSCoder) {
        let xAxis = aDecoder.decodeFloatForKey("xAxis")
        let yAxis = aDecoder.decodeFloatForKey("yAxis")
        self.init(state: DpadState(xAxis: xAxis, yAxis: yAxis))
    }
    
    public func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeFloat(state.xAxis, forKey: "xAxis")
        aCoder.encodeFloat(state.yAxis, forKey: "yAxis")
    }
}