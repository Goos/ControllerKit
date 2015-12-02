//
//  UDPConnection.swift
//  ControllerKit
//
//  Created by Robin Goos on 30/11/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

final class UDPConnection : NSObject, GCDAsyncUdpSocketDelegate {
    private(set) var socket: GCDAsyncUdpSocket!
    private(set) var connected: Bool
    private(set) var listening: Bool
    var port: UInt16 {
        return socket.localPort()
    }
    private var inputChannels: [String:_ReadableChannel] = [:]
    private var outputChannels: [String:_WritableChannel] = [:]
    
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
    
    func registerReadChannel<T: Marshallable>(identifier: UInt16, host: String? = nil, type: T.Type) -> UDPReadChannel<T>? {
        let h = host ?? socket.connectedHost()
        
        if h != nil {
            let key = keyForHost(h!, port: nil, identifier: identifier)
            let channel = UDPReadChannel<T>(identifier: identifier, host: h!, port: nil)
            inputChannels[key] = channel
            return channel
        } else {
            return nil
        }
    }
    
    func registerWriteChannel<T: Marshallable>(identifier: UInt16, host: String? = nil, port: UInt16? = nil, type: T.Type) -> UDPWriteChannel<T>? {
        let h = host ?? socket.connectedHost()
        let p = port ?? socket.connectedPort()
        
        if h != nil {
            let key = keyForHost(h!, port: p, identifier: identifier)
            let channel = UDPWriteChannel<T>(connection: self, identifier: identifier, host: h!, port: p)
            outputChannels[key] = channel
            return channel
        } else {
            return nil
        }
    }
    
    func registerWriteChannel<T: Marshallable>(identifier: UInt16, address: NSData, type: T.Type) -> UDPWriteChannel<T>? {
        var host: NSString?
        var port = UInt16()
        GCDAsyncSocket.getHost(&host, port: &port, fromAddress: address)
        return registerWriteChannel(identifier, host: host as? String, port: port, type: type)
    }
    
    func deregisterReadChannel<T: Marshallable>(channel: UDPReadChannel<T>) {
        if let host = channel.host, port = channel.port {
            let key = keyForHost(host, port: port, identifier: channel.identifier)
            inputChannels.removeValueForKey(key)
        }
    }
    
    func deregisterWriteChannel<T: Marshallable>(channel: UDPWriteChannel<T>) {
        if let host = channel.host, port = channel.port {
            let key = keyForHost(host, port: port, identifier: channel.identifier)
            outputChannels.removeValueForKey(key)
        }
    }
    
    private func send(payload: NSData, host: String? = nil, port: UInt16? = nil) {
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

struct Datagram<T: Marshallable> : Marshallable {
    let payload: T
    let identifier: UInt16
    
    init(payload: T, identifier: UInt16) {
        self.payload = payload
        self.identifier = identifier
    }
    
    init?(data: NSData) {
        var buffer = ReadBuffer(data: data)
        guard let ident: UInt16 = buffer.read(),
            length: Int32 = buffer.read(),
            payload: T = buffer.read(Int(length)) else {
            return nil
        }
        
        self.init(payload: payload, identifier: ident)
    }
    
    func marshal() -> NSData {
        var buffer = WriteBuffer()
        let payloadData = payload.marshal()
        buffer << identifier
        buffer << Int32(payloadData.length)
        buffer << payloadData
        return buffer.data
    }
}

final class UDPReadChannel<T: Marshallable> : ReadableChannel, _ReadableChannel {
    typealias MessageType = T
    let identifier: UInt16
    let host: String?
    let port: UInt16?
    var onReceive: ((T) -> ())?
    
    init(identifier: UInt16, host: String?, port: UInt16?) {
        self.identifier = identifier
        self.host = host
        self.port = port
    }
    
    func receive(data: NSData) {
        if let datagram = Datagram<T>(data: data) {
            onReceive?(datagram.payload)
        }
    }
}

final class UDPWriteChannel<T: Marshallable> : WritableChannel, _WritableChannel {
    typealias MessageType = T
    let identifier: UInt16
    let host: String?
    let port: UInt16?
    unowned let connection: UDPConnection
    
    init(connection: UDPConnection, identifier: UInt16, host: String?, port: UInt16?) {
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

private func keyForHost(host: String, port: UInt16?, identifier: UInt16) -> String {
    if let p = port {
        return "\(host):\(p)/\(identifier)"
    } else {
        return "\(host)/\(identifier)"
    }
}