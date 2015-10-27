//
//  RemoteInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import Act

final class RemoteSessionMessage : Message {
    let type = "RemoteSessionMessage"
    let command: AsyncCommand
    let data: AnyObject
    
    init(command: AsyncCommand, data: AnyObject) {
        self.command = command
        self.data = data
    }
}

func RemoteControllerInteractor(_: Actor<ControllerState>, message: Message, next: (Message) -> ()) {
    guard let m = message as? RemoteSessionMessage else {
        return
    }
    
    switch(m.data) {
    case let remote as ButtonChanged:
        next(remote)
    case let remote as DpadChanged:
        next(remote)
    default:
        break
    }
}

// MARK: Encoding / Decoding
enum EncodingStructError: ErrorType {
    case InvalidSize
}

func encode<T>(var value: T) -> NSData {
    return withUnsafePointer(&value) { p in
        NSData(bytes: p, length: sizeofValue(value))
    }
}

func decode<T>(data: NSData) throws -> T {
    guard data.length == sizeof(T) else {
        throw EncodingStructError.InvalidSize
    }

    let pointer = UnsafeMutablePointer<T>.alloc(1)
    data.getBytes(pointer, length: data.length)

    return pointer.move()
}