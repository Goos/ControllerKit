//
//  Marshalling.swift
//  ControllerKit
//
//  Created by Robin Goos on 30/11/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

protocol Marshallable {
    init?(data: NSData)
    func marshal() -> NSData
}

protocol PrimitiveMarshallable {
    typealias SwappedType
    static var size: Int { get }
    
    init(swapped: SwappedType)
    init()
    
    func swapped() -> SwappedType
}

extension PrimitiveMarshallable {
    static var size: Int {
        return sizeof(self)
    }
}

struct WriteBuffer {
    var data: NSMutableData
    var length: Int {
        return data.length
    }
    
    init() {
        data = NSMutableData()
    }
    
    mutating func write<T: PrimitiveMarshallable where T.SwappedType : PrimitiveMarshallable>(value: T) {
        var swapped = value.swapped()
        let size = T.SwappedType.size
        data.appendBytes(&swapped, length: size)
    }
    
    mutating func write<T: Marshallable>(value: T) {
        let marshalled = value.marshal()
        data.appendData(marshalled)
    }
}

struct ReadBuffer {
    var data: NSData
    var offset: Int = 0
    var length: Int {
        return data.length
    }
    
    init(data: NSData) {
        self.data = data
    }
    
    mutating func read<T: PrimitiveMarshallable where T.SwappedType : PrimitiveMarshallable>() -> T? {
        var value = T.SwappedType()
        let size = T.SwappedType.size
        if offset + size <= length {
            data.getBytes(&value, range: NSMakeRange(offset, size))
            offset += size
            return T(swapped: value)
        } else {
            return nil
        }
    }
    
    mutating func read<T: Marshallable>(length: Int? = nil) -> T? {
        let l = length ?? data.length - offset
        let remaining = data.subdataWithRange(NSMakeRange(offset, l))
        offset = data.length
        return T(data: remaining)
    }
}

prefix operator << {}
prefix func <<<T: PrimitiveMarshallable where T.SwappedType : PrimitiveMarshallable>(inout buffer: ReadBuffer) -> T? {
    return buffer.read()
}

prefix func <<<T: Marshallable>(inout buffer: ReadBuffer) -> T? {
    return buffer.read()
}

func <<<T: PrimitiveMarshallable where T.SwappedType : PrimitiveMarshallable>(inout buffer: WriteBuffer, value: T) {
    buffer.write(value)
}

func <<<T: Marshallable>(inout buffer: WriteBuffer, value: T) {
    buffer.write(value)
}

extension Int16 : PrimitiveMarshallable {
    typealias SwappedType = UInt16
    
    init(swapped: SwappedType) {
        let swapped = CFSwapInt16LittleToHost(swapped)
        self.init(bitPattern: swapped)
    }
    
    func swapped() -> SwappedType {
        let unsigned = UInt16(bitPattern: self)
        return CFSwapInt16HostToLittle(unsigned)
    }
}

extension Int32 : PrimitiveMarshallable {
    typealias SwappedType = UInt32
    
    init(swapped: SwappedType) {
        let swapped = CFSwapInt32LittleToHost(swapped)
        self.init(bitPattern: swapped)
    }
    
    func swapped() -> SwappedType {
        let unsigned = UInt32(bitPattern: self)
        return CFSwapInt32HostToLittle(unsigned)
    }
}

extension Int64 : PrimitiveMarshallable {
    typealias SwappedType = UInt64
    
    init(swapped: SwappedType) {
        let swapped = CFSwapInt64LittleToHost(swapped)
        self.init(bitPattern: swapped)
    }
    
    func swapped() -> SwappedType {
        let unsigned = UInt64(bitPattern: self)
        return CFSwapInt64HostToLittle(unsigned)
    }
}

extension UInt16 : PrimitiveMarshallable {
    typealias SwappedType = UInt16
    
    init(swapped: SwappedType) {
        self.init(CFSwapInt16LittleToHost(swapped))
    }
    
    func swapped() -> SwappedType {
        return CFSwapInt16HostToLittle(self)
    }
}

extension UInt32 : PrimitiveMarshallable {
    typealias SwappedType = UInt32
    
    init(swapped: SwappedType) {
        self.init(CFSwapInt32LittleToHost(swapped))
    }
    
    func swapped() -> SwappedType {
        return CFSwapInt32HostToLittle(self)
    }
}

extension UInt64 : PrimitiveMarshallable {
    typealias SwappedType = UInt64
    
    init(swapped: SwappedType) {
        self.init(CFSwapInt64LittleToHost(swapped))
    }
    
    func swapped() -> SwappedType {
        return CFSwapInt64HostToLittle(self)
    }
}

extension Float : PrimitiveMarshallable {
    typealias SwappedType = CFSwappedFloat32
    
    init(swapped: SwappedType) {
        self.init(CFConvertFloat32SwappedToHost(swapped))
    }
    
    func swapped() -> SwappedType {
        return CFConvertFloat32HostToSwapped(self)
    }
}

extension Double : PrimitiveMarshallable {
    typealias SwappedType = CFSwappedFloat64
    
    init(swapped: SwappedType) {
        self.init(CFConvertFloat64SwappedToHost(swapped))
    }
    
    func swapped() -> SwappedType {
        return CFConvertFloat64HostToSwapped(self)
    }
}

extension CFSwappedFloat32 : PrimitiveMarshallable {
    typealias SwappedType = Float
    
    init(swapped: SwappedType) {
        self.init(v: CFConvertFloat32HostToSwapped(swapped).v)
    }
    
    func swapped() -> SwappedType {
        return CFConvertFloat32SwappedToHost(self)
    }
}

extension CFSwappedFloat64 : PrimitiveMarshallable {
    typealias SwappedType = Double
    
    init(swapped: SwappedType) {
        self.init(v: CFConvertFloat64HostToSwapped(swapped).v)
    }
    
    func swapped() -> SwappedType {
        return CFConvertFloat64SwappedToHost(self)
    }
}

extension String : Marshallable {
    init?(data: NSData) {
        self.init(data: data, encoding: NSUTF8StringEncoding)
    }
    
    func marshal() -> NSData {
        return self.dataUsingEncoding(NSUTF8StringEncoding)!
    }
}

extension NSData : Marshallable {
    func marshal() -> NSData {
        return self
    }
}