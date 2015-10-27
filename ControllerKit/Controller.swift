//
//  Controller.swift
//  ControllerKit
//
//  Created by Robin Goos on 25/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import GameController
import Act

public enum ConnectionStatus : Int {
    case Disconnected
    case Connecting
    case Connected
}

public final class ButtonState : Hashable {
    public let value: Float
    public let pressed: Bool
    
    public var hashValue: Int {
        return value.hashValue + pressed.hashValue
    }
    
    public init(value: Float, pressed: Bool) {
        self.value = value
        self.pressed = pressed
    }
}


public func ==(lhs: ButtonState, rhs: ButtonState) -> Bool {
    return lhs.hashValue == rhs.hashValue
}

public final class DpadState : Hashable {
    public let xAxis: Float
    public let yAxis: Float
    
    public var hashValue: Int {
        return xAxis.hashValue * 3 + yAxis.hashValue * 5
    }
    
    public init(xAxis: Float, yAxis: Float) {
        self.xAxis = xAxis
        self.yAxis = yAxis
    }
}

public func ==(lhs: DpadState, rhs: DpadState) -> Bool {
    return lhs.hashValue == rhs.hashValue
}

public enum ControllerType {
    case Micro
    case Regular
    case Extended
}

public final class ControllerState {
    var status: ConnectionStatus
    public let type: ControllerType
    
    public let buttonA: Observable<ButtonState>
    public let buttonB: Observable<ButtonState>
    public let buttonX: Observable<ButtonState>
    public let buttonY: Observable<ButtonState>
    
    public let leftShoulder: Observable<ButtonState>
    public let rightShoulder: Observable<ButtonState>
    
    public let dpad: Observable<DpadState>
    
    public init() {
        status = .Disconnected
        type = .Regular
        
        buttonA = Observable(ButtonState(value: 0, pressed: false))
        buttonB = Observable(ButtonState(value: 0, pressed: false))
        buttonX = Observable(ButtonState(value: 0, pressed: false))
        buttonY = Observable(ButtonState(value: 0, pressed: false))
        
        leftShoulder = Observable(ButtonState(value: 0, pressed: false))
        rightShoulder = Observable(ButtonState(value: 0, pressed: false))
        
        dpad = Observable(DpadState(xAxis: 0, yAxis: 0))
    }
}

public func ControllerStateReducer(state: ControllerState, message: Message) -> ControllerState {
    switch(message) {
    case let m as ConnectionChanged:
        state.status = m.status
    case let m as ButtonChanged:
        switch(m.button) {
        case .A: state.buttonA.value = m.state
        case .B: state.buttonA.value = m.state
        case .X: state.buttonA.value = m.state
        case .Y: state.buttonA.value = m.state
        case .LS: state.buttonA.value = m.state
        case .RS: state.buttonA.value = m.state
        }
    case let m as DpadChanged:
        state.dpad.value = m.state
    default:
        break
    }
    
    return state
}

public final class Controller {
    internal let inputHandler: Actor<ControllerState>
    public var state: ControllerState {
        return inputHandler.state
    }
    
    public init(nativeController: GCController, queue: Queueable = dispatch_get_main_queue().queueable()) {
        inputHandler = Actor(initialState: ControllerState(), interactors: [], reducer: ControllerStateReducer, processingQueue: queue)
        bind(nativeController, inputHandler)
    }
    
    public init(inputHandler: Actor<ControllerState>) {
        self.inputHandler = inputHandler
    }
}

public func ControllerInputHandler(initialState: ControllerState = ControllerState(), processingQueue: Queueable? = nil) -> Actor<ControllerState> {
    return Actor(initialState: initialState, interactors: [], reducer: ControllerStateReducer, processingQueue: processingQueue)
}