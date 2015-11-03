//
//  RemoteInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import Act

extension JoystickChanged : Marshallable {
    init?(data: NSData) {
        let typeSize = sizeof(UInt16)
        let axisSize = sizeof(CFSwappedFloat32)
        if data.length < typeSize + axisSize * 2 {
            return nil
        }
        var rawType = UInt16()
        var swappedX = CFSwappedFloat32()
        var swappedY = CFSwappedFloat32()
        data.getBytes(&rawType, length: typeSize)
        data.getBytes(&swappedX, range: NSMakeRange(typeSize, axisSize))
        data.getBytes(&swappedY, range: NSMakeRange(typeSize + axisSize, axisSize))
        
        if let type = JoystickType(rawValue: CFSwapInt16LittleToHost(rawType)) {
            let xAxis = CFConvertFloat32SwappedToHost(swappedX)
            let yAxis = CFConvertFloat32SwappedToHost(swappedY)
            self.state = JoystickState(xAxis: xAxis, yAxis: yAxis)
            self.joystick = type
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        var rawType = CFSwapInt16HostToLittle(joystick.rawValue)
        var swappedX = CFConvertFloat32HostToSwapped(state?.xAxis ?? 0.0)
        var swappedY = CFConvertFloat32HostToSwapped(state?.yAxis ?? 0.0)
        data.appendBytes(&rawType, length: sizeof(UInt16))
        data.appendBytes(&swappedX, length: sizeof(CFSwappedFloat32))
        data.appendBytes(&swappedY, length: sizeof(CFSwappedFloat32))
        return data
    }
}

extension ButtonChanged : Marshallable {
    init?(data: NSData) {
        let typeSize = sizeof(UInt16)
        let valueSize = sizeof(CFSwappedFloat32)
        let pressedSize = sizeof(Bool)
        if data.length < typeSize + valueSize + pressedSize {
            return nil
        }
        var rawType = UInt16()
        var swappedValue = CFSwappedFloat32()
        var pressed = Bool()
        data.getBytes(&rawType, length: typeSize)
        data.getBytes(&swappedValue, length: valueSize)
        data.getBytes(&pressed, range: NSMakeRange(valueSize, pressedSize))
        let value = CFConvertFloat32SwappedToHost(swappedValue)
        
        if let button = ButtonType(rawValue: CFSwapInt16LittleToHost(rawType)) {
            self.button = button
            self.state = ButtonState(value: value, pressed: pressed)
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        var rawType = CFSwapInt16HostToLittle(button.rawValue)
        var swappedVal = CFConvertFloat32HostToSwapped(state?.value ?? 0.0)
        var pressed = state?.pressed ?? false
        data.appendBytes(&rawType, length: sizeof(UInt16))
        data.appendBytes(&swappedVal, length: sizeof(Float))
        data.appendBytes(&pressed, length: sizeof(Bool))
        return data
    }
}

extension SetControllerName : Marshallable {
    init?(data: NSData) {
        if let name = String(data: data, encoding: NSUTF8StringEncoding) {
            self.name = name
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        if let encoded = name?.dataUsingEncoding(name!.smallestEncoding) {
            data.appendData(encoded)
        }
        return data
    }
}

extension SetGamepadType : Marshallable {
    init?(data: NSData) {
        var rawType = UInt16()
        data.getBytes(&rawType, length: sizeof(UInt16))
        if let gamepad = GamepadType(rawValue: rawType) {
            self.controllerType = gamepad
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        var rawType = controllerType.rawValue
        data.appendBytes(&rawType, length: sizeof(UInt16))
        return data
    }
}

//struct RemoteInputThrottler