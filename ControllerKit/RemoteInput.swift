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
    let controllerIndex: UInt16
    
    init(message: T, controllerIndex: UInt16) {
        self.message = message
        self.controllerIndex = controllerIndex
    }
    
    init?(data: NSData) {
        var swappedIdx = UInt16()
        data.getBytes(&swappedIdx, range: NSMakeRange(0, sizeof(UInt16)))
        let idx = CFSwapInt16LittleToHost(swappedIdx)
        let messageData = data.subdataWithRange(NSMakeRange(sizeof(UInt16), data.length - sizeof(UInt16)))
        if let message = T(data: messageData) {
            self.init(message: message, controllerIndex: idx)
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        let messageData = message.marshal()
        var swappedIdx = CFSwapInt16HostToLittle(controllerIndex)
        data.appendBytes(&swappedIdx, length: sizeof(UInt16))
        data.appendData(messageData)
        return data
    }
}

struct ControllerConnectedMessage : Message, Marshallable {
    let type = "ControllerConnectedMessage"
    let index: UInt16
    let layout: GamepadLayout
    let name: String?
    
    init(index: UInt16, layout: GamepadLayout, name: String? = nil) {
        self.index = index
        self.layout = layout
        self.name = name
    }
    
    init?(data: NSData) {
        let uint16Size = sizeof(UInt16)
        var swappedIdx = UInt16()
        var swappedLayout = UInt16()
        var offset: Int = 0
        data.getBytes(&swappedIdx, length: uint16Size)
        offset += uint16Size
        data.getBytes(&swappedLayout, range: NSMakeRange(offset, uint16Size))
        offset += uint16Size
        
        guard let layout = GamepadLayout(rawValue: CFSwapInt16LittleToHost(swappedLayout)) else {
            return nil
        }
        
        self.index = CFSwapInt16LittleToHost(swappedIdx)
        self.layout = layout
        
        if (data.length > offset) {
            let nameData = data.subdataWithRange(NSMakeRange(offset, data.length - offset))
            if let name = String(data: nameData, encoding: NSUTF8StringEncoding) {
                self.name = name
            } else {
                self.name = nil
            }
        } else {
            self.name = nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        var swappedIdx = CFSwapInt16HostToLittle(index)
        var swappedLayout = CFSwapInt16HostToLittle(layout.rawValue)
        data.appendBytes(&swappedIdx, length: sizeof(UInt16))
        data.appendBytes(&swappedLayout, length: sizeof(UInt16))
        if let encodedName = name?.dataUsingEncoding(NSUTF8StringEncoding) {
            data.appendData(encodedName)
        }
        return data
    }
}

extension JoystickMessage : Marshallable {
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
        var swappedX = CFConvertFloat32HostToSwapped(state.xAxis)
        var swappedY = CFConvertFloat32HostToSwapped(state.yAxis)
        data.appendBytes(&rawType, length: sizeof(UInt16))
        data.appendBytes(&swappedX, length: sizeof(CFSwappedFloat32))
        data.appendBytes(&swappedY, length: sizeof(CFSwappedFloat32))
        return data
    }
}

extension ButtonMessage : Marshallable {
    init?(data: NSData) {
        let typeSize = sizeof(UInt16)
        let valueSize = sizeof(CFSwappedFloat32)
        let pressedSize = sizeof(Bool)
        if data.length < typeSize + valueSize + pressedSize {
            return nil
        }
        var rawType = UInt16()
        var swappedValue = CFSwappedFloat32()
        data.getBytes(&rawType, length: typeSize)
        data.getBytes(&swappedValue, length: valueSize)
        let value = CFConvertFloat32SwappedToHost(swappedValue)
        
        if let button = ButtonType(rawValue: CFSwapInt16LittleToHost(rawType)) {
            self.button = button
            self.value = value
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        var rawType = CFSwapInt16HostToLittle(button.rawValue)
        var swappedVal = CFConvertFloat32HostToSwapped(value)
        data.appendBytes(&rawType, length: sizeof(UInt16))
        data.appendBytes(&swappedVal, length: sizeof(CFSwappedFloat32))
        return data
    }
}

extension ControllerNameMessage : Marshallable {
    init?(data: NSData) {
        if let name = String(data: data, encoding: NSUTF8StringEncoding) {
            self.name = name
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        if let encoded = name?.dataUsingEncoding(NSUTF8StringEncoding) {
            data.appendData(encoded)
        }
        return data
    }
}

extension GamepadLayoutMessage : Marshallable {
    init?(data: NSData) {
        var rawType = UInt16()
        data.getBytes(&rawType, length: sizeof(UInt16))
        if let layout = GamepadLayout(rawValue: CFSwapInt16LittleToHost(rawType)) {
            self.layout = layout
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        var swappedLayout = CFSwapInt16HostToLittle(layout.rawValue)
        data.appendBytes(&swappedLayout, length: sizeof(UInt16))
        return data
    }
}

extension GamepadMessage : Marshallable {
    init?(data: NSData) {
        var offset : Int = 0
        let floatSize = sizeof(CFSwappedFloat32)
        var swappedLayout: UInt16 = 0
        data.getBytes(&swappedLayout, length: sizeof(UInt16))
        guard let layout = GamepadLayout(rawValue: CFSwapInt16(swappedLayout)) else {
            return nil
        }
        offset += sizeof(UInt16)
        
        var gamepad = GamepadState(layout: layout)
        var swappedA = CFSwappedFloat32()
        var swappedX = CFSwappedFloat32()
        var swappedDpadX = CFSwappedFloat32()
        var swappedDpadY = CFSwappedFloat32()
        data.getBytes(&swappedA, range: NSMakeRange(offset, floatSize))
        offset += floatSize
        data.getBytes(&swappedX, range: NSMakeRange(offset, floatSize))
        offset += floatSize
        data.getBytes(&swappedDpadX, range: NSMakeRange(offset, floatSize))
        offset += floatSize
        data.getBytes(&swappedDpadY, range: NSMakeRange(offset, floatSize))
        offset += floatSize
        gamepad.buttonA = CFConvertFloat32SwappedToHost(swappedA)
        gamepad.buttonX = CFConvertFloat32SwappedToHost(swappedX)
        gamepad.dpad.xAxis = CFConvertFloat32SwappedToHost(swappedDpadX)
        gamepad.dpad.yAxis = CFConvertFloat32SwappedToHost(swappedDpadY)
        
        if (layout == .Regular || layout == .Extended) {
            var swappedB = CFSwappedFloat32()
            var swappedY = CFSwappedFloat32()
            var swappedLS = CFSwappedFloat32()
            var swappedRS = CFSwappedFloat32()
            data.getBytes(&swappedB, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            data.getBytes(&swappedY, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            data.getBytes(&swappedLS, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            data.getBytes(&swappedRS, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            gamepad.buttonB = CFConvertFloat32SwappedToHost(swappedB)
            gamepad.buttonY = CFConvertFloat32SwappedToHost(swappedY)
            gamepad.leftTrigger = CFConvertFloat32SwappedToHost(swappedLS)
            gamepad.rightTrigger = CFConvertFloat32SwappedToHost(swappedRS)
        }
        
        if (layout == .Extended) {
            var swappedLT = CFSwappedFloat32()
            var swappedRT = CFSwappedFloat32()
            var swappedLTX = CFSwappedFloat32()
            var swappedLTY = CFSwappedFloat32()
            var swappedRTX = CFSwappedFloat32()
            var swappedRTY = CFSwappedFloat32()
            data.getBytes(&swappedLT, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            data.getBytes(&swappedRT, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            data.getBytes(&swappedLTX, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            data.getBytes(&swappedLTY, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            data.getBytes(&swappedRTX, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            data.getBytes(&swappedRTY, range: NSMakeRange(offset, floatSize))
            offset += floatSize
            gamepad.leftTrigger = CFConvertFloat32SwappedToHost(swappedLT)
            gamepad.rightTrigger = CFConvertFloat32SwappedToHost(swappedRT)
            gamepad.leftThumbstick.xAxis = CFConvertFloat32SwappedToHost(swappedLTX)
            gamepad.leftThumbstick.yAxis = CFConvertFloat32SwappedToHost(swappedLTY)
            gamepad.rightThumbstick.xAxis = CFConvertFloat32SwappedToHost(swappedRTX)
            gamepad.rightThumbstick.yAxis = CFConvertFloat32SwappedToHost(swappedRTY)
        }
        
        state = gamepad
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        let floatSize = sizeof(CFSwappedFloat32)
        var swappedLayout = CFSwapInt16(state.layout.rawValue)
        var swappedA = CFConvertFloat32HostToSwapped(state.buttonA)
        var swappedX = CFConvertFloat32HostToSwapped(state.buttonX)
        var swappedDpadX = CFConvertFloat32HostToSwapped(state.dpad.xAxis)
        var swappedDpadY = CFConvertFloat32HostToSwapped(state.dpad.yAxis)
        data.appendBytes(&swappedLayout, length: sizeof(UInt16))
        data.appendBytes(&swappedA, length: floatSize)
        data.appendBytes(&swappedX, length: floatSize)
        data.appendBytes(&swappedDpadX, length: floatSize)
        data.appendBytes(&swappedDpadY, length: floatSize)
        
        if (state.layout == .Regular || state.layout == .Extended) {
            var swappedB = CFConvertFloat32HostToSwapped(state.buttonB)
            var swappedY = CFConvertFloat32HostToSwapped(state.buttonY)
            var swappedLS = CFConvertFloat32HostToSwapped(state.leftShoulder)
            var swappedRS = CFConvertFloat32HostToSwapped(state.rightShoulder)
            data.appendBytes(&swappedB, length: floatSize)
            data.appendBytes(&swappedY, length: floatSize)
            data.appendBytes(&swappedLS, length: floatSize)
            data.appendBytes(&swappedRS, length: floatSize)
        }
        
        if (state.layout == .Extended) {
            var swappedLT = CFConvertFloat32HostToSwapped(state.leftTrigger)
            var swappedRT = CFConvertFloat32HostToSwapped(state.rightTrigger)
            var swappedLTX = CFConvertFloat32HostToSwapped(state.leftThumbstick.xAxis)
            var swappedLTY = CFConvertFloat32HostToSwapped(state.leftThumbstick.yAxis)
            var swappedRTX = CFConvertFloat32HostToSwapped(state.rightThumbstick.xAxis)
            var swappedRTY = CFConvertFloat32HostToSwapped(state.rightThumbstick.yAxis)
            data.appendBytes(&swappedLT, length: floatSize)
            data.appendBytes(&swappedRT, length: floatSize)
            data.appendBytes(&swappedLTX, length: floatSize)
            data.appendBytes(&swappedLTY, length: floatSize)
            data.appendBytes(&swappedRTX, length: floatSize)
            data.appendBytes(&swappedRTY, length: floatSize)
        }
        
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
    var joystickInputs: [JoystickType:ThrottledBuffer<JoystickMessage>] = [:]
    var buttonInputs: [ButtonType:ThrottledBuffer<ButtonMessage>] = [:]
    
    init(interval: Double) {
        self.interval = interval
    }
    
    func receive(inputHandler: Actor<GamepadState>, message: Message, next: (Message) -> ()) {
        switch(message) {
        case let m as JoystickMessage:
            let j  = m.joystick
            var buf = joystickInputs[j]
            if buf == nil {
                buf = ThrottledBuffer(interval: interval) {
                    next($0)
                }
                joystickInputs[j] = buf
            }
            
            buf!.insert(m)
        case let m as ButtonMessage:
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