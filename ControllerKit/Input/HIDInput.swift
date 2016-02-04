//
//  HIDInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 30/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//
// (Very much) inspired by Slembcke's work over here:
// https://github.com/slembcke/CCController/blob/master/CCController/CCController.m

import Foundation
import Act

#if os(OSX)
import IOKit.hid

enum HIDVendor : Int {
    case Sony = 0x054C
    case Microsoft = 0x045E
    case MadCatz = 0x1BAD
}

enum HIDProduct : Int {
    case Dualshock4 = 0x5C4
    case Xbox360Wired = 0x028E
    case Xbox360Wireless = 0x028F
    case Xbox360ArcadeStick = 0xF038
}

let kHIDAxisDeadZone: Float = 0.2

final class HIDControllerSource : ControllerSource {
    private let runLoopMode = "ControllerKitHIDInput"
    let manager: IOHIDManager
    let runLoop: NSRunLoop
    
    private var controllers: [Int:Controller] = [:]
    
    private var onControllerConnected: ((Controller) -> ())? = nil
    private var onControllerDisconnected: ((Controller) -> ())? = nil
    private var onError: ((NSError) -> ())? = nil
    
    init(runLoop: NSRunLoop = NSRunLoop.mainRunLoop()) {
        self.runLoop = runLoop
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0).takeRetainedValue()
    }
    
    deinit {
        stop()
    }
    
    func listen(controllerConnected: (Controller) -> (), controllerDisconnected: (Controller) -> (), error: (NSError) -> ()) {
        onControllerConnected = controllerConnected
        onControllerDisconnected = controllerDisconnected
        onError = error
        
        let status = IOHIDManagerOpen(manager, 0)
        if status != kIOReturnSuccess {
            let error = NSError(domain: "com.controllerkit.hid", code: 0, userInfo: nil)
            onError?(error)
            return
        }
        
        /* Holy casting, batman! Working with C-APIs in Swift is like jumping 
            through hoops held up in the jaws of crocodiles. */
        let context = unsafeBitCast(self, UnsafeMutablePointer<Void>.self)
        /* C-style callbacks can't capture references, so the workaround is to send 
        the 'self'-reference as a void pointer to the context parameter. */
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { (context, result, sender, device) in
            if result == kIOReturnSuccess {
                let source = unsafeBitCast(context, HIDControllerSource.self)
                source.deviceConnected(device)
            }
        }, context)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { (context, result, sender, device) in
            if result == kIOReturnSuccess {
                let source = unsafeBitCast(context, HIDControllerSource.self)
                source.deviceDisconnected(device)
            }
        }, context)
        
        // CFArray & CFDictionary magically bridges without effort though.
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController]
        ])
        
        IOHIDManagerScheduleWithRunLoop(manager, runLoop.getCFRunLoop(), kCFRunLoopDefaultMode)
    }
    
    func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, runLoop.getCFRunLoop(), runLoopMode)
        IOHIDManagerClose(manager, 0)
    }
    
    func deviceConnected(device: IOHIDDevice) {
        guard let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey).takeUnretainedValue() as? Int,
            productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey).takeUnretainedValue() as? Int,
            vendor = HIDVendor(rawValue: vendorID),
            product = HIDProduct(rawValue: productID)
        else {
            return
        }
        
        var transformer: HIDInputTransformer?
        var axisMin: Int = 0
        var axisMax: Int = 256
        
        if vendor == .Sony && product == .Dualshock4 {
            transformer = HIDInputTransformer(
                leftThumbstickIDs: (UInt32(kHIDUsage_GD_X), UInt32(kHIDUsage_GD_Y)),
                rightThumbstickIDs: (UInt32(kHIDUsage_GD_Z), UInt32(kHIDUsage_GD_Rz)),
                leftTriggerID: UInt32(kHIDUsage_GD_Rx),
                rightTriggerID: UInt32(kHIDUsage_GD_Ry),
                leftShoulderID: 0x05,
                rightShoulderID: 0x06,
                usesHatSwitch: true,
                dpadIDs: (0, 0, 0, 0),
                buttonPauseID: 0x0A,
                buttonAID: 0x02,
                buttonBID: 0x03,
                buttonXID: 0x01,
                buttonYID: 0x04
            )
        } else if (vendor == .Microsoft || vendor == .MadCatz) && (product == .Xbox360Wired || product == .Xbox360Wireless || product == .Xbox360ArcadeStick) {
            transformer = HIDInputTransformer(
                leftThumbstickIDs: (UInt32(kHIDUsage_GD_X), UInt32(kHIDUsage_GD_Y)),
                rightThumbstickIDs: (UInt32(kHIDUsage_GD_Rx), UInt32(kHIDUsage_GD_Ry)),
                leftTriggerID: UInt32(kHIDUsage_GD_Z),
                rightTriggerID: UInt32(kHIDUsage_GD_Rz),
                leftShoulderID: 0x05,
                rightShoulderID: 0x06,
                usesHatSwitch: false,
                dpadIDs: (0x0C, 0x0F, 0x0D, 0x0E),
                buttonPauseID: 0x09,
                buttonAID: 0x01,
                buttonBID: 0x02,
                buttonXID: 0x03,
                buttonYID: 0x04
            )
            
            axisMin = -(1 << 15)
            axisMax = (1 << 15)
        }
        
        if let transf = transformer {
            if let element = IOHIDDeviceGetAxisElement(device, elementID: Int(transf.leftThumbstickIDs.x)) {
                IOHIDDeviceCalibrateAxisElement(element, calibration: (-1.0, 1.0), saturation: (axisMin, axisMax), deadZonePercent: kHIDAxisDeadZone)
            }
            if let element = IOHIDDeviceGetAxisElement(device, elementID: Int(transf.leftThumbstickIDs.y)) {
                IOHIDDeviceCalibrateAxisElement(element, calibration: (1.0, -1.0), saturation: (axisMin, axisMax), deadZonePercent: kHIDAxisDeadZone)
            }
            if let element = IOHIDDeviceGetAxisElement(device, elementID: Int(transf.rightThumbstickIDs.x)) {
                IOHIDDeviceCalibrateAxisElement(element, calibration: (-1.0, 1.0), saturation: (axisMin, axisMax), deadZonePercent: kHIDAxisDeadZone)
            }
            if let element = IOHIDDeviceGetAxisElement(device, elementID: Int(transf.rightThumbstickIDs.y)) {
                IOHIDDeviceCalibrateAxisElement(element, calibration: (1.0, -1.0), saturation: (axisMin, axisMax), deadZonePercent: kHIDAxisDeadZone)
            }
            
            if let element = IOHIDDeviceGetAxisElement(device, elementID: Int(transf.leftTriggerID)) {
                IOHIDDeviceCalibrateAxisElement(element, calibration: (0.0, 1.0), saturation: (0, 256), deadZonePercent: 0.0)
            }
            if let element = IOHIDDeviceGetAxisElement(device, elementID: Int(transf.rightTriggerID)) {
                IOHIDDeviceCalibrateAxisElement(element, calibration: (0.0, 1.0), saturation: (0, 256), deadZonePercent: 0.0)
            }
            
            let inputHandler = ObservableActor<GamepadState>(initialState: GamepadState(layout: .Extended), transformers: [transf.receive], reducer: GamepadStateReducer)
            let controller = Controller(inputHandler: inputHandler)
            
            IOHIDDeviceRegisterInputValueCallback(device, { (context, result, sender, value) in
                let controller = unsafeBitCast(context, Controller.self)
                let message = HIDInputMessage(value: value)
                controller.inputHandler.send(message)
            }, unsafeBitCast(controller, UnsafeMutablePointer<Void>.self))
            
            let deviceId = IOHIDDeviceGetProperty(device, kIOHIDUniqueIDKey).takeRetainedValue() as! Int
            controllers[deviceId] = controller
            
            onControllerConnected?(controller)
        }
    }
    
    func deviceDisconnected(device: IOHIDDevice) {
        let deviceId = IOHIDDeviceGetProperty(device, kIOHIDUniqueIDKey).takeRetainedValue() as! Int
        if let controller = controllers.removeValueForKey(deviceId) {
            onControllerDisconnected?(controller)
        }
    }
}

func IOHIDDeviceGetAxisElement(device: IOHIDDeviceRef, elementID: Int) -> IOHIDElementRef? {
    let matching = [
        kIOHIDElementUsagePageKey: kHIDPage_GenericDesktop,
		kIOHIDElementUsageKey: elementID
    ]
    let elements = IOHIDDeviceCopyMatchingElements(device, matching, 0).takeRetainedValue()
    if CFArrayGetCount(elements) == 0 {
        return nil
    }
    
    let elementPtr = CFArrayGetValueAtIndex(elements, 0)
    let element = unsafeBitCast(elementPtr, IOHIDElementRef.self)
    return element
}

func IOHIDDeviceCalibrateAxisElement(element: IOHIDElementRef, calibration: (Float, Float), saturation: (Int, Int), deadZonePercent: Float) {
    IOHIDElementSetProperty(element, kIOHIDElementCalibrationMinKey, calibration.0)
    IOHIDElementSetProperty(element, kIOHIDElementCalibrationMaxKey, calibration.1)
    
    IOHIDElementSetProperty(element, kIOHIDElementCalibrationSaturationMinKey, saturation.0)
    IOHIDElementSetProperty(element, kIOHIDElementCalibrationSaturationMaxKey, saturation.1)
    
    if deadZonePercent > 0.0 {
        let mid = Float(saturation.0 + saturation.1) / 2.0
        let deadZone = Float(saturation.1 - saturation.0) * (deadZonePercent / 2.0)
        
        IOHIDElementSetProperty(element, kIOHIDElementCalibrationDeadZoneMinKey, mid - deadZone)
        IOHIDElementSetProperty(element, kIOHIDElementCalibrationDeadZoneMaxKey, mid + deadZone)
    }
}

struct HIDInputMessage : Message {
    let type = "HIDInputMessage"
    let value: IOHIDValueRef
}

private let kButtonUsagePage = UInt32(kHIDPage_Button)
private let kJoystickUsagePage = UInt32(kHIDPage_GenericDesktop)
private let kHatSwitchUsage = UInt32(kHIDUsage_GD_Hatswitch)

struct HIDInputTransformer {
    let leftThumbstickIDs: (x: UInt32, y: UInt32)
    let rightThumbstickIDs: (x: UInt32, y: UInt32)
    
    let leftTriggerID: UInt32
    let rightTriggerID: UInt32
    
    let leftShoulderID: UInt32
    let rightShoulderID: UInt32
    
    let usesHatSwitch: Bool
    let dpadIDs: (up: UInt32, right: UInt32, down: UInt32, left: UInt32)
    
    let buttonPauseID: UInt32
    let buttonAID: UInt32
    let buttonBID: UInt32
    let buttonXID: UInt32
    let buttonYID: UInt32
    
    func receive(inputHandler: Actor<GamepadState>, message: Message, next: (Message) -> ()) {
        guard let m = message as? HIDInputMessage else {
            return next(message)
        }
        
        let currentState = inputHandler.state
        
        let element = IOHIDValueGetElement(m.value).takeUnretainedValue()
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let state = IOHIDValueGetIntegerValue(m.value)
        let analog = Float(IOHIDValueGetScaledValue(m.value, UInt32(kIOHIDValueScaleTypeCalibrated)))
        
        switch(usagePage) {
        case kButtonUsagePage:
            var button: ButtonType?
            var xAxis: Float?
            var yAxis: Float?
            
            switch(usage) {
            case buttonPauseID: button = .Pause
            case buttonAID: button = .A
            case buttonBID: button = .B
            case buttonXID: button = .X
            case buttonYID: button = .Y
            case leftShoulderID: button = .LS
            case rightShoulderID: button = .RS
            case dpadIDs.up: yAxis = Float(state)
            case dpadIDs.right: xAxis = Float(state)
            case dpadIDs.down: yAxis = -Float(state)
            case dpadIDs.left: xAxis = -Float(state)
            default: break
            }
            
            if !usesHatSwitch && (xAxis != nil || yAxis != nil) {
                let dpad = currentState.dpad
                let joystickState = JoystickState(xAxis: xAxis ?? dpad.xAxis, yAxis: yAxis ?? dpad.yAxis)
                next(JoystickMessage(joystick: .Dpad, state: joystickState))
            } else if button != nil {
                next(ButtonMessage(button: button!, value: Float(state)))
            }
        case kJoystickUsagePage:
            var button: ButtonType?
            var joystick: JoystickType?
            var axes: (x: Float, y: Float) = (0.0, 0.0)
            
            switch(usage) {
            case leftThumbstickIDs.x:
                joystick = .LeftThumbstick
                axes = (analog, currentState.leftThumbstick.yAxis)
            case leftThumbstickIDs.y:
                joystick = .LeftThumbstick
                axes = (currentState.leftThumbstick.xAxis, analog)
            case rightThumbstickIDs.x:
                joystick = .RightThumbstick
                axes = (analog, currentState.rightThumbstick.yAxis)
            case rightThumbstickIDs.y:
                joystick = .RightThumbstick
                axes = (currentState.rightThumbstick.xAxis, analog)
            case leftTriggerID: button = .LT
            case rightTriggerID: button = .RT
            case kHatSwitchUsage:
                if (usesHatSwitch) {
                    joystick = .Dpad
                    switch(state) {
                    case 0: axes = (0.0, 1.0)
                    case 1: axes = (1.0, 1.0)
                    case 2: axes = (1.0, 0.0)
                    case 3: axes = (1.0, -1.0)
                    case 4: axes = (0.0, -1.0)
                    case 5: axes = (-1.0, -1.0)
                    case 6: axes = (-1.0, 0.0)
                    case 7: axes = (-1.0, 1.0)
                    default: axes = (0.0, 0.0)
                    }
                }
            default: break
            }
            
            if joystick != nil {
                let joystickState = JoystickState(xAxis: axes.x, yAxis: axes.y)
                next(JoystickMessage(joystick: joystick!, state: joystickState))
            } else if button != nil {
                next(ButtonMessage(button: button!, value: analog))
            }
        default: break
        }
    }
}

#else
typealias HIDControllerManager = Void
#endif
