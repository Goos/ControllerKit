//
//  Connection.swift
//  ControllerKit
//
//  Created by Robin Goos on 31/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

protocol Marshallable {
    init?(data: NSData)
    func marshal() -> NSData
}

private protocol ReadableChannel {
    func receive(data: NSData)
}

private protocol WritableChannel {}

struct Datagram<T: Marshallable> : Marshallable {
    let payload: T
    let identifier: UInt16
    
    init(payload: T, identifier: UInt16) {
        self.payload = payload
        self.identifier = identifier
    }
    
    init?(data: NSData) {
        var swappedIdent = UInt16()
        var swappedLength = UInt32()
        data.getBytes(&swappedIdent, range: NSMakeRange(0, sizeof(UInt16)))
        data.getBytes(&swappedLength, range: NSMakeRange(sizeof(UInt16), sizeof(UInt32)))
        let ident = CFSwapInt16LittleToHost(swappedIdent)
        let length = CFSwapInt32LittleToHost(swappedLength)
        let payloadData = data.subdataWithRange(NSMakeRange(sizeof(UInt16) + sizeof(UInt32), Int(length)))
        if let payload = T(data: payloadData) {
            self.init(payload: payload, identifier: ident)
        } else {
            return nil
        }
    }
    
    func marshal() -> NSData {
        let data = NSMutableData()
        let payloadData = payload.marshal()
        var ident = CFSwapInt16HostToLittle(identifier)
        var length = CFSwapInt32LittleToHost(UInt32(payloadData.length))
        data.appendBytes(&ident, length: sizeof(UInt16))
        data.appendBytes(&length, length: sizeof(UInt32))
        data.appendData(payloadData)
        return data
    }
}

final class ReadChannel<T: Marshallable> : ReadableChannel {
    let identifier: UInt16
    let host: String?
    let port: UInt16?
    var onReceive: ((T) -> ())?
    
    init(identifier: UInt16, host: String?, port: UInt16?) {
        self.identifier = identifier
        self.host = host
        self.port = port
    }
    
    private func receive(data: NSData) {
        if let datagram = Datagram<T>(data: data) {
            onReceive?(datagram.payload)
        }
    }
    
    func receive(callback: (T) -> ()) {
        self.onReceive = callback
    }
}

final class WriteChannel<T: Marshallable> : WritableChannel {
    let identifier: UInt16
    let host: String?
    let port: UInt16?
    unowned let connection: WriteConnection
    
    init(connection: WriteConnection, identifier: UInt16, host: String?, port: UInt16?) {
        self.identifier = identifier
        self.host = host
        self.port = port
        self.connection = connection
    }
    
    func send(payload: T) {
        let datagram = Datagram(payload: payload, identifier: identifier)
        connection.send(datagram.marshal(), host: host, port: port)
    }
}

protocol ReadConnection : class {
    func listen(localPort: UInt16, success: (() -> ())?, error: ((NSError) -> ())?, disconnect: (() -> ())?)
    func registerReadChannel<T: Marshallable>(identifier: UInt16, host: String?, type: T.Type) -> ReadChannel<T>?
    func deregisterReadChannel<T: Marshallable>(channel: ReadChannel<T>)
}

protocol WriteConnection : class {
    func connect(host: String, port: UInt16, success: (() -> ())?, error: ((NSError) -> ())?, disconnect: (() -> ())?)
    func connect(address: NSData, success: (() -> ())?, error: ((NSError) -> ())?, disconnect: (() -> ())?)
    func disconnect()
    func send(data: NSData, host: String?, port: UInt16?)
    func registerWriteChannel<T: Marshallable>(identifier: UInt16, host: String?, port: UInt16?, type: T.Type) -> WriteChannel<T>?
    func deregisterWriteChannel<T: Marshallable>(channel: WriteChannel<T>)
}

typealias MultiplexConnection = protocol<ReadConnection, WriteConnection>

private func keyForHost(host: String, port: UInt16?, identifier: UInt16) -> String {
    if let p = port {
        return "\(host):\(p)/\(identifier)"
    } else {
        return "\(host)/\(identifier)"
    }
}

final class UDPConnection : NSObject, MultiplexConnection, GCDAsyncUdpSocketDelegate {
    private(set) var socket: GCDAsyncUdpSocket!
    private(set) var connected: Bool
    private(set) var listening: Bool
    var port: UInt16 {
        return socket.localPort()
    }
    private var inputChannels: [String:ReadableChannel] = [:]
    private var outputChannels: [String:WritableChannel] = [:]
    
    var onSuccess: (() -> ())?
    var onError: ((NSError) -> ())?
    var onDisconnect: (() -> ())?
    
    convenience override init() {
        self.init(socketQueue: dispatch_queue_create("com.controllerkit.socket_queue", DISPATCH_QUEUE_CONCURRENT), delegateQueue: dispatch_queue_create("com.controllerkit.delegate_queue", DISPATCH_QUEUE_SERIAL))
    }
    
    init(socketQueue: dispatch_queue_t, delegateQueue: dispatch_queue_t) {
        connected = false
        listening = false
        super.init()
        socket = GCDAsyncUdpSocket(delegate: self, delegateQueue: delegateQueue, socketQueue: socketQueue)
    }
    
    func connect(host: String, port: UInt16, success: (() -> ())?, error: ((NSError) -> ())?, disconnect: (() -> ())?) {
        if connected { return }
        
        onSuccess = success
        onError = error
        onDisconnect = disconnect
        
        do {
            try socket.connectToHost(host, onPort: port)
        } catch let err as NSError {
            onError?(err)
        }
    }
    
    func connect(address: NSData, success: (() -> ())?, error: ((NSError) -> ())?, disconnect: (() -> ())?) {
        if connected { return }
        
        onSuccess = success
        onError = error
        onDisconnect = disconnect
        
        do {
            try socket.connectToAddress(address)
        } catch let err as NSError {
            onError?(err)
        }
    }
    
    func disconnect() {
        socket.close()
    }
    
    func listen(localPort: UInt16, success: (() -> ())? = nil, error: ((NSError) -> ())? = nil, disconnect: (() -> ())? = nil) {
        if listening { return }
        
        onSuccess = success
        onError = error
        onDisconnect = disconnect
        
        do {
            try socket.bindToPort(localPort)
            try socket.beginReceiving()
            success?()
        } catch let error as NSError  {
            onError?(error)
        } catch {}
    }
    
    func registerReadChannel<T: Marshallable>(identifier: UInt16, host: String? = nil, type: T.Type) -> ReadChannel<T>? {
        let h = host ?? socket.connectedHost()
        
        if h != nil {
            let key = keyForHost(h!, port: nil, identifier: identifier)
            let channel = ReadChannel<T>(identifier: identifier, host: h!, port: nil)
            inputChannels[key] = channel
            return channel
        } else {
            return nil
        }
    }
    
    func registerWriteChannel<T: Marshallable>(identifier: UInt16, host: String? = nil, port: UInt16? = nil, type: T.Type) -> WriteChannel<T>? {
        let h = host ?? socket.connectedHost()
        let p = port ?? socket.connectedPort()
        
        if h != nil {
            let key = keyForHost(h!, port: p, identifier: identifier)
            let channel = WriteChannel<T>(connection: self, identifier: identifier, host: h!, port: p)
            outputChannels[key] = channel
            return channel
        } else {
            return nil
        }
    }
    
    func registerWriteChannel<T: Marshallable>(identifier: UInt16, address: NSData, type: T.Type) -> WriteChannel<T>? {
        var host: NSString?
        var port = UInt16()
        GCDAsyncSocket.getHost(&host, port: &port, fromAddress: address)
        return registerWriteChannel(identifier, host: host as? String, port: port, type: type)
    }
    
    func deregisterReadChannel<T: Marshallable>(channel: ReadChannel<T>) {
        if let host = channel.host, port = channel.port {
            let key = keyForHost(host, port: port, identifier: channel.identifier)
            inputChannels.removeValueForKey(key)
        }
    }
    
    func deregisterWriteChannel<T: Marshallable>(channel: WriteChannel<T>) {
        if let host = channel.host, port = channel.port {
            let key = keyForHost(host, port: port, identifier: channel.identifier)
            outputChannels.removeValueForKey(key)
        }
    }
    
    func send(payload: NSData, host: String? = nil, port: UInt16? = nil) {
        let h = host ?? socket.connectedHost()
        let p = port ?? socket.connectedPort()
        if h != nil {
            socket.sendData(payload, toHost: h!, port: p, withTimeout: -1, tag: 0)
        }
    }
    
    // MARK: GCDAsyncUdpSocketDelegate
    func udpSocket(sock: GCDAsyncUdpSocket, didConnectToAddress address: NSData) {
        onSuccess?()
    }
    
    func udpSocket(sock: GCDAsyncUdpSocket, didNotConnect error: NSError) {
        onError?(error)
    }
    
    func udpSocketDidClose(sock: GCDAsyncUdpSocket, withError error: NSError) {
        onDisconnect?()
    }
    
    func udpSocket(sock: GCDAsyncUdpSocket!, didReceiveData data: NSData!, fromAddress address: NSData!, withFilterContext filterContext: AnyObject!) {
        var host: NSString?
        var port = UInt16()
        GCDAsyncSocket.getHost(&host, port: &port, fromAddress: address)
        
        // Peeking at the data header to find the channel identifier.
        var swappedIdent = UInt16()
        data.getBytes(&swappedIdent, length: sizeof(UInt16))
        let ident = CFSwapInt16LittleToHost(swappedIdent)
        
        let key = keyForHost(host as! String, port: nil, identifier: ident)
        // If a matching channel was found, let that channel handle it.
        if let channel = inputChannels[key] {
            channel.receive(data)
        }
    }
}

final class TCPConnection : NSObject, MultiplexConnection, GCDAsyncSocketDelegate {
    private(set) var socket: GCDAsyncSocket!
    private(set) var connected: Bool
    private var inputChannels: [UInt16:ReadableChannel] = [:]
    private var outputChannels: [UInt16:WritableChannel] = [:]
    
    var onSuccess: (() -> ())?
    var onError: ((NSError) -> ())?
    var onDisconnect: (() -> ())?
    
    convenience override init() {
        self.init(socketQueue: dispatch_queue_create("com.controllerkit.socket_queue", DISPATCH_QUEUE_CONCURRENT), delegateQueue: dispatch_queue_create("com.controllerkit.delegate_queue", DISPATCH_QUEUE_SERIAL))
    }
    
    init(socketQueue: dispatch_queue_t, delegateQueue: dispatch_queue_t) {
        connected = false
        super.init()
        socket = GCDAsyncSocket(delegate: self, delegateQueue: delegateQueue, socketQueue: socketQueue)
    }
    
    init(socket: GCDAsyncSocket, delegateQueue: dispatch_queue_t) {
        self.socket = socket
        connected = true
        super.init()
        socket.synchronouslySetDelegate(self, delegateQueue: delegateQueue)
        socket.readDataWithTimeout(-1, tag: 0)
    }
    
    func connect(host: String, port: UInt16, success: (() -> ())?, error onError: ((NSError) -> ())?, disconnect onDisconnect: (() -> ())?) {
        if connected { return }
        
        self.onSuccess = success
        self.onError = onError
        self.onDisconnect = onDisconnect
        
        do {
            try socket.connectToHost(host, onPort: port)
        } catch let err as NSError {
            onError?(err)
        }
    }
    
    func connect(address: NSData, success: (() -> ())?, error onError: ((NSError) -> ())?, disconnect onDisconnect: (() -> ())?) {
        if connected { return }
        
        self.onSuccess = success
        self.onError = onError
        self.onDisconnect = onDisconnect
        
        do {
            try socket.connectToAddress(address)
        } catch let err as NSError {
            onError?(err)
        }
    }
    
    func disconnect() {
        socket.disconnect()
    }
    
    func send(payload: NSData, host: String? = nil, port: UInt16? = nil) {
        socket.writeData(payload, withTimeout: -1, tag: 0)
    }
    
    func listen(localPort: UInt16, success: (() -> ())? = nil, error: ((NSError) -> ())? = nil, disconnect: (() -> ())? = nil) {
    }
    
    func registerReadChannel<T: Marshallable>(identifier: UInt16, host: String? = nil, type: T.Type) -> ReadChannel<T>? {
        let channel = ReadChannel<T>(identifier: identifier, host: socket.connectedHost, port: socket.connectedPort)
        inputChannels[identifier] = channel
        return channel
    }
    
    func registerWriteChannel<T: Marshallable>(identifier: UInt16, host: String? = nil, port: UInt16? = nil, type: T.Type) -> WriteChannel<T>? {
        let channel = WriteChannel<T>(connection: self, identifier: identifier, host: socket.connectedHost, port: socket.connectedPort)
        outputChannels[identifier] = channel
        return channel
    }
    
    func registerWriteChannel<T: Marshallable>(identifier: UInt16, type: T.Type) -> WriteChannel<T> {
        return registerWriteChannel(identifier, host: nil, port: nil, type: type)!
    }
    
    func deregisterReadChannel<T: Marshallable>(channel: ReadChannel<T>) {
        inputChannels.removeValueForKey(channel.identifier)
    }
    
    func deregisterWriteChannel<T: Marshallable>(channel: WriteChannel<T>) {
        outputChannels.removeValueForKey(channel.identifier)
    }
    
    // MARK: GCDAsyncSocketDelegate
    func socket(sock: GCDAsyncSocket!, didConnectToHost host: String!, port: UInt16) {
        socket.readDataWithTimeout(-1, tag: 0)
        onSuccess?()
    }
    
    func socketDidDisconnect(sock: GCDAsyncSocket!, withError err: NSError!) {
        onDisconnect?()
    }
    
    func socket(sock: GCDAsyncSocket!, didWriteDataWithTag tag: Int) {
    
    }
    
    func socket(sock: GCDAsyncSocket!, didReadData data: NSData!, withTag tag: Int) {
        // Peeking at the data header to find the channel identifier.
        var swappedIdent = UInt16()
        data.getBytes(&swappedIdent, length: sizeof(UInt16))
        let ident = CFSwapInt16LittleToHost(swappedIdent)
        // If a matching channel was found, let that channel handle it.
        if let channel = inputChannels[ident] {
            channel.receive(data)
        }
    }
}