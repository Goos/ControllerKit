//
//  RemoteInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import Act

struct RemoteSessionMessage : Message {
    let type = "RemoteSessionMessage"
    let data: NSData
}

func RemoteControllerInteractor(_: Actor<ControllerState>, message: Message, next: (Message) -> ()) {
    guard let m = message as? RemoteSessionMessage else {
        return
    }
    
    do {
        let decodedMessage: Message = try decode(m.data)
        next(decodedMessage)
    } catch {}
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