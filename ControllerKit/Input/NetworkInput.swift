//
//  NetworkInput.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation
import Act

final class NetworkPeer {
    var controllers: [UInt16:Controller] = [:]
    let host: String
    let nameChannel: TCPReadChannel<NetworkMessage<ControllerNameMessage>>
    let gamepadChannel: UDPReadChannel<NetworkMessage<GamepadMessage>>
    var disconnectTimer: NSTimer?
    
    init(host: String, nameChannel: TCPReadChannel<NetworkMessage<ControllerNameMessage>>, gamepadChannel: UDPReadChannel<NetworkMessage<GamepadMessage>>) {
        self.host = host
        self.nameChannel = nameChannel
        self.gamepadChannel = gamepadChannel
        
        nameChannel.onReceive = { [weak self] message in
            if let controller = self?.controllers[message.controllerIndex] {
                controller.name = message.message.name
            }
        }
        
        gamepadChannel.onReceive = { [weak self] message in
            if let controller = self?.controllers[message.controllerIndex] {
                controller.inputHandler.send(message.message)
            }
        }
    }
}

public struct ServiceTXTRecord : Marshallable {
    let kInputPortKey = "INPUT_PORT"
    let inputPort: UInt16
    
    init(inputPort: UInt16) {
        self.inputPort = inputPort
    }
    
    init?(data: NSData) {
        let dictionary = NSNetService.dictionaryFromTXTRecordData(data)
        guard let portData = dictionary[kInputPortKey] else {
            return nil
        }
        
        var port = UInt16(0)
        portData.getBytes(&port, length: sizeof(UInt16))
        
        if port == 0 {
            return nil
        } else {
            inputPort = CFSwapInt16LittleToHost(port)
        }
    }
    
    func marshal() -> NSData {
        var swappedPort = CFSwapInt16HostToLittle(inputPort)
        let portData = NSData(bytes: &swappedPort, length: sizeof(UInt16))
        return NSNetService.dataFromTXTRecordDictionary([kInputPortKey: portData])
    }
}

let kLocalDomain = "local."

final class NetworkControllerSource : NSObject, ControllerSource, NSNetServiceDelegate, GCDAsyncSocketDelegate {
    private let name: String
    private let serviceIdentifier: String
    private var running = false
    
    private var peers: [String:NetworkPeer] = [:]
    
    private var netService: NSNetService?
    private let discoverySocket: GCDAsyncSocket
    private let inputConnection: UDPConnection
    
    private var connections: Set<TCPConnection> = []
    
    private let networkQueue: dispatch_queue_t
    private let inputQueue: dispatch_queue_t
    
    private var onControllerConnected: ((Controller) -> ())? = nil
    private var onControllerDisconnected: ((Controller) -> ())? = nil
    private var onError: ((NSError) -> ())? = nil
    
    init(name: String, serviceIdentifier: String = "controllerkit", networkQueue: dispatch_queue_t, inputQueue: dispatch_queue_t) {
        self.name = name
        self.serviceIdentifier = serviceIdentifier
        
        self.networkQueue = networkQueue
        self.inputQueue = inputQueue
        
        discoverySocket = GCDAsyncSocket(socketQueue: networkQueue)
        inputConnection = UDPConnection(socketQueue: networkQueue, delegateQueue: inputQueue)
        
        super.init()
        
        discoverySocket.synchronouslySetDelegate(self, delegateQueue: inputQueue)
    }
    
    deinit {
        stop()
    }
    
    func listen(controllerConnected: (Controller) -> (), controllerDisconnected: (Controller) -> (), error: (NSError) -> ()) {
        guard !running else {
            return
        }
        
        onControllerConnected = controllerConnected
        onControllerDisconnected = controllerDisconnected
        onError = error
        
        do {
            try discoverySocket.acceptOnPort(0)
            let port = discoverySocket.localPort
            
            inputConnection.listen(0, success: { [unowned self] in
                let txtRecord = ServiceTXTRecord(inputPort: self.inputConnection.port)
                let serviceType = "_\(self.serviceIdentifier)._tcp"
                self.netService = NSNetService(domain: kLocalDomain, type: serviceType, name: self.name, port: Int32(port))
                self.netService?.setTXTRecordData(txtRecord.marshal())
                self.netService?.delegate = self
                self.netService?.includesPeerToPeer = false
                self.netService?.publish()
                self.addApplicationStateListeners()
            }, error: { [unowned self] err in
                self.running = false
                self.onError?(err)
            })
        } catch let error as NSError {
            self.running = false
            self.onError?(error)
        }
        
        running = true
    }
    
    func addApplicationStateListeners() {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationWillResignActive:", name: "UIApplicationWillResignActiveNotification", object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationWillEnterForeground:", name: "UIApplicationWillEnterForegroundNotification", object: nil)
    }
    
    func removeApplicationStateListeners() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func stop() {
        guard running else {
            return
        }
        
        netService?.stop()
        for conn in connections {
            conn.disconnect()
        }
        running = false
        removeApplicationStateListeners()
    }
    
    // MARK: NSNetServiceDelegate
    func netServiceDidPublish(sender: NSNetService) {
    }
    
    func netService(sender: NSNetService, didNotPublish errorDict: [String : NSNumber]) {
        if let code = errorDict[NSNetServicesErrorCode] as? Int {
            let error = NSError(domain: "com.controllerkit.netservice", code: code, userInfo: errorDict)
            onError?(error)
        }
    }
    
    func netServiceDidStop(sender: NSNetService) {
    }
    
    // MARK: GCDAsyncSocketDelegate
    func socket(sock: GCDAsyncSocket!, didAcceptNewSocket newSocket: GCDAsyncSocket!) {
        newSocket.performBlock {
            newSocket.enableBackgroundingOnSocket()
        }
        let tcpConnection = TCPConnection(socket: newSocket, delegateQueue: inputQueue)
        connections.insert(tcpConnection)
        
        let host = newSocket.connectedHost
        
        if let peer = peers[host] {
            self.peerReconnected(peer)
        } else {
            // Channels used by the peer to connect & disconnect controllers.
            let cc = tcpConnection.registerReadChannel(1, type: ControllerConnectedMessage.self)
            let dc = tcpConnection.registerReadChannel(2, type: ControllerDisconnectedMessage.self)
            
            cc.onReceive = { [unowned self, unowned tcpConnection] message in
                self.receivedControllerConnectedMessage(message, connection: tcpConnection)
            }
            
            dc.onReceive = { [unowned self, unowned tcpConnection] message in
                self.receivedControllerDisconnectedMessage(message, connection: tcpConnection)
            }
        }
        
        tcpConnection.onDisconnect = { [weak self] in
            if let peer = self?.peers[host] {
                self?.peerDisconnected(peer)
            }
        }
        
        tcpConnection.onError = { [weak self] err in
            self?.onError?(err)
        }
    }
    
    func newSocketQueueForConnectionFromAddress(address: NSData!, onSocket sock: GCDAsyncSocket!) -> dispatch_queue_t! {
        return networkQueue
    }
    
    private func receivedControllerConnectedMessage(message: ControllerConnectedMessage, connection: TCPConnection) {
        let host = connection.socket.connectedHost
        var peer = peers[host]
        if peer == nil {
            /* Registering a channel on the open UDP connection, listening
                for controller input from this specific host. */
            let gc = inputConnection.registerReadChannel(1, host: host, type: NetworkMessage<GamepadMessage>.self)
            // Registering a channel on the TCP connection for controller name changes.
            let nc = connection.registerReadChannel(3, type: NetworkMessage<ControllerNameMessage>.self)
            
            peer = NetworkPeer(host: host, nameChannel: nc, gamepadChannel: gc)
            peers[host] = peer
        }
        
        if let controller = peer!.controllers[message.index] {
            controller.status = .Connected
        } else {
            let inputHandler = ControllerInputHandler(GamepadState(layout: .Regular), processingQueue: self.inputQueue.queueable())
            let controller = Controller(inputHandler: inputHandler)
            controller.name = message.name
            peer!.controllers[message.index] = controller
            
            onControllerConnected?(controller)
            /* TODO: Acknowledge the message, letting the peer know if it was
                accepted or not, based on the version of the peer and server. */
        }
    }
    
    private func receivedControllerDisconnectedMessage(message: ControllerDisconnectedMessage, connection: TCPConnection) {
        let host = connection.socket.connectedHost
        guard let peer = peers[host] else {
            return
        }
        
        if let controller = peer.controllers[message.index] {
            onControllerDisconnected?(controller)
            peer.controllers.removeValueForKey(message.index)
        }
    }
    
    /* Whenever a peer disconnects, it has a short grace period before
        the delegate is notified that the controllers are disconnected.
        This is in order to make it slightly more resilient to network
        drops and the likes. */
    private func peerDisconnected(peer: NetworkPeer) {
        for (_, controller) in peer.controllers {
            controller.status = .Disconnected
        }
        
        peer.disconnectTimer = NSTimer.setTimeout(12) {
            for (index, controller) in peer.controllers {
                self.onControllerDisconnected?(controller)
                peer.controllers.removeValueForKey(index)
            }
            
            self.inputConnection.deregisterReadChannel(peer.gamepadChannel)
            self.peers.removeValueForKey(peer.host)
        }
    }
    
    /* If the peer reconnects before a short timer, the controllers
        are reconnected. */
    private func peerReconnected(peer: NetworkPeer) {
        peer.disconnectTimer?.invalidate()
        
        for (_, controller) in peer.controllers {
            controller.status = .Connected
        }
    }
    
    // MARK: Application events
    func applicationWillResignActive(notification: NSNotification) {
        if running {
            netService?.stop()
        }
    }
    
    func applicationWillEnterForeground(notification: NSNotification) {
        if running {
            netService?.publish()
        }
    }
}

struct NetworkMessage<T: protocol<Message, Marshallable>> : Message, Marshallable {
    let type = "NetworkMessage"
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
            buttonX: Float = buffer.read(),
            dpadX: Float = buffer.read(),
            dpadY: Float = buffer.read()
            else {
            return nil
        }
        
        var gamepad = GamepadState(layout: layout)
        gamepad.buttonA = buttonA
        gamepad.buttonX = buttonX
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
        buffer << state.buttonX
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