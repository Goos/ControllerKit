//
//  RemoteInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import Act

struct RemoteMessage<T: protocol<Message, Marshallable>> : Message, Marshallable {
    let type = "RemoteMessage"
    let message: T
    let controllerIdx: UInt16
    
    init(message: T, controllerIdx: UInt16) {
        self.message = message
        self.controllerIdx = controllerIdx
    }
    
    init?(data: NSData) {
        var swappedIdx = UInt16()
        data.getBytes(&swappedIdx, range: NSMakeRange(0, sizeof(UInt16)))
        let idx = CFSwapInt16LittleToHost(swappedIdx)
        let messageData = data.subdataWithRange(NSMakeRange(sizeof(UInt16), data.length - sizeof(UInt16)))
        if let message = T(data: messageData) {
            self.init(message: message, controllerIdx: idx)
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        let messageData = message.marshal()
        var swappedIdx = CFSwapInt16HostToLittle(controllerIdx)
        data.appendBytes(&swappedIdx, length: sizeof(UInt16))
        data.appendData(messageData)
        return data
    }
}

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
            self.gamepad = gamepad
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        var rawType = gamepad.rawValue
        data.appendBytes(&rawType, length: sizeof(UInt16))
        return data
    }
}

final class ThrottledBuffer<T> {
    let interval: NSTimeInterval
    private var element: T?
    private var waiting: Bool
    private let queue: dispatch_queue_t
    private let handler: (T) -> ()
    
    init(interval: NSTimeInterval, queue: dispatch_queue_t = dispatch_queue_create("com.controllerkit.throttler", DISPATCH_QUEUE_SERIAL), handler: (T) -> ()) {
        self.interval = interval
        self.queue = queue
        self.handler = handler
        element = nil
        waiting = false
    }
    
    func insert(element: T) {
        dispatch_async(queue) {
            self.element = element
            if !self.waiting {
                self.handler(element)
                self.element = nil
                
                self.waiting = true
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(self.interval * Double(NSEC_PER_SEC))), self.queue) {
                    self.waiting = false
                    if let elem = self.element {
                        self.handler(elem)
                    }
                }
            }
        }
    }
}

public class ThrottlingTransformer {
    let interval: Double
    var joystickInputs: [JoystickType:ThrottledBuffer<JoystickChanged>] = [:]
    var buttonInputs: [ButtonType:ThrottledBuffer<ButtonChanged>] = [:]
    
    init(interval: Double) {
        self.interval = interval
    }
    
    func receive(inputHandler: Actor<GamepadState>, message: Message, next: (Message) -> ()) {
        switch(message) {
        case let m as JoystickChanged:
            let j  = m.joystick
            var buf = joystickInputs[j]
            if buf == nil {
                buf = ThrottledBuffer(interval: interval) {
                    next($0)
                }
                joystickInputs[j] = buf
            }
            
            buf!.insert(m)
        case let m as ButtonChanged:
            let b  = m.button
            var buf = buttonInputs[b]
            if buf == nil {
                buf = ThrottledBuffer(interval: interval, handler: {
                    next($0)
                })
                buttonInputs[b] = buf
            }
            
            buf!.insert(m)
        default:
            next(message)
        }
    }
}