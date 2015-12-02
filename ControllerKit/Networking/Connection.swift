//
//  Connection.swift
//  ControllerKit
//
//  Created by Robin Goos on 31/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

protocol _ReadableChannel {
    func receive(data: NSData)
}

protocol _WritableChannel {}

protocol Channel {
    typealias MessageType
}

protocol ReadableChannel : Channel {
    var onReceive: ((MessageType) -> ())? { get set }
}

protocol WritableChannel : Channel {
    func send(message: MessageType)
}

//protocol ReadConnection : class {
//    func listen(localPort: UInt16, success: (() -> ())?, error: ((NSError) -> ())?, disconnect: (() -> ())?)
//    func registerReadChannel<T: Marshallable, C: ReadableChannel where C.MessageType == T>(identifier: UInt16, host: String?, type: T.Type) -> C?
//    func deregisterReadChannel<T: Marshallable, C: ReadableChannel where C.MessageType == T>(channel: C)
//}
//
//protocol WriteConnection : class {
//    func connect(host: String, port: UInt16, success: (() -> ())?, error: ((NSError) -> ())?, disconnect: (() -> ())?)
//    func connect(address: NSData, success: (() -> ())?, error: ((NSError) -> ())?, disconnect: (() -> ())?)
//    func disconnect()
//    func send(data: NSData, host: String?, port: UInt16?)
//    func registerWriteChannel<T: Marshallable, C: WritableChannel where C.MessageType == T>(identifier: UInt16, host: String?, port: UInt16?, type: T.Type) -> C?
//    func deregisterWriteChannel<T: Marshallable, C: WritableChannel where C.MessageType == T>(channel: C)
//}

//typealias MultiplexConnection = protocol<ReadConnection, WriteConnection>
