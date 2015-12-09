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
        var buffer = ReadBuffer(data: data)
        guard let idx: UInt16 = buffer.read(),
            message: T = buffer.read() else {
            return nil
        }
        
        self.init(message: message, controllerIndex: idx)
    }
    
    func marshal() -> NSData {
        var buffer = WriteBuffer()
        buffer << controllerIndex
        buffer << message
        return buffer.data
    }
}

struct ControllerConnectedMessage : Message, Marshallable {
    let type = "ControllerConnectedMessage"
    let index: UInt16
    let layout: GamepadLayout
    let version: UInt16
    let name: String?
    
    init(index: UInt16, layout: GamepadLayout, name: String? = nil) {
        self.index = index
        self.layout = layout
        self.name = name
        self.version = UInt16(ControllerKitVersionNumber)
    }
    
    init?(data: NSData) {
        var buffer = ReadBuffer(data: data)
        guard let idx: UInt16 = buffer.read(),
            rawLayout: UInt16 = buffer.read(),
            version: UInt16 = buffer.read(),
            layout = GamepadLayout(rawValue: rawLayout) else {
            return nil
        }
        
        self.index = idx
        self.layout = layout
        self.version = version
        self.name = buffer.read()
    }
    
    func marshal() -> NSData {
        var buffer = WriteBuffer()
        buffer << index
        buffer << layout.rawValue
        buffer << version
        if let n = name {
            buffer << n
        }
        return buffer.data
    }
}

struct ControllerDisconnectedMessage : Message, Marshallable {
    let type = "ControllerDisconnectedMessage"
    let index: UInt16
    
    init(index: UInt16) {
        self.index = index
    }
    
    init?(data: NSData) {
        var buffer = ReadBuffer(data: data)
        guard let idx: UInt16 = buffer.read() else {
            return nil
        }
        
        self.index = idx
    }
    
    func marshal() -> NSData {
        var buffer = WriteBuffer()
        buffer << index
        return buffer.data
    }
}

extension JoystickMessage : Marshallable {
    init?(data: NSData) {
        var buffer = ReadBuffer(data: data)
        guard let rawType: UInt16 = buffer.read(),
            joystickType = JoystickType(rawValue: rawType),
            xAxis: Float = buffer.read(),
            yAxis: Float = buffer.read() else {
            return nil
        }
        
        self.state = JoystickState(xAxis: xAxis, yAxis: yAxis)
        self.joystick = joystickType
    }
    
    func marshal() -> NSData {
        var buffer = WriteBuffer()
        buffer << joystick.rawValue
        buffer << state.xAxis
        buffer << state.yAxis
        return buffer.data
    }
}

extension ButtonMessage : Marshallable {
    init?(data: NSData) {
        var buffer = ReadBuffer(data: data)
        guard let rawType: UInt16 = buffer.read(),
            buttonType = ButtonType(rawValue: rawType),
            value: Float = buffer.read() else {
            return nil
        }
        
        self.button = buttonType
        self.value = value
    }
    
    func marshal() -> NSData {
        var buffer = WriteBuffer()
        buffer << button.rawValue
        buffer << value
        return buffer.data
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

extension GamepadMessage : Marshallable {
    init?(data: NSData) {
        var buffer = ReadBuffer(data: data)
        guard let rawLayout: UInt16 = buffer.read(),
            layout = GamepadLayout(rawValue: rawLayout),
            buttonA: Float = buffer.read(),
            buttonB: Float = buffer.read(),
            dpadX: Float = buffer.read(),
            dpadY: Float = buffer.read()
            else {
            return nil
        }
        
        var gamepad = GamepadState(layout: layout)
        gamepad.buttonA = buttonA
        gamepad.buttonB = buttonB
        gamepad.dpad = JoystickState(xAxis: dpadX, yAxis: dpadY)
        
        if layout == .Regular || layout == .Extended {
            gamepad.buttonB = buffer.read() ?? 0.0
            gamepad.buttonY = buffer.read() ?? 0.0
            gamepad.leftTrigger = buffer.read() ?? 0.0
            gamepad.rightTrigger = buffer.read() ?? 0.0
        }
        
        if layout == .Extended {
            gamepad.leftShoulder = buffer.read() ?? 0.0
            gamepad.rightShoulder = buffer.read() ?? 0.0
            
            let ltx: Float = buffer.read() ?? 0.0
            let lty: Float = buffer.read() ?? 0.0
            gamepad.leftThumbstick = JoystickState(xAxis: ltx, yAxis: lty)
            
            let rtx: Float = buffer.read() ?? 0.0
            let rty: Float = buffer.read() ?? 0.0
            gamepad.rightThumbstick = JoystickState(xAxis: rtx, yAxis: rty)
        }
        
        state = gamepad
    }
    
    func marshal() -> NSData {
        var buffer = WriteBuffer()
        buffer << state.layout.rawValue
        buffer << state.buttonA
        buffer << state.buttonB
        buffer << state.dpad.xAxis
        buffer << state.dpad.yAxis
        
        if (state.layout == .Regular || state.layout == .Extended) {
            buffer << state.buttonB
            buffer << state.buttonY
            buffer << state.leftTrigger
            buffer << state.rightTrigger
        }
        
        if (state.layout == .Extended) {
            buffer << state.leftShoulder
            buffer << state.rightShoulder
            buffer << state.leftThumbstick.xAxis
            buffer << state.leftThumbstick.yAxis
            buffer << state.rightThumbstick.xAxis
            buffer << state.rightThumbstick.yAxis
        }
        
        return buffer.data
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