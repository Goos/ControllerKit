//
//  Observable.swift
//  ControllerKit
//
//  Created by Robin Goos on 25/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

private struct BoxedObserver<T> : Hashable {
    let closure: T
    let hashValue: Int
    
    init(_ closure: T) {
        self.closure = closure
        self.hashValue = Int(arc4random_uniform(UInt32(Int32.max)))
    }
}

private func ==<T>(lhs: BoxedObserver<T>, rhs: BoxedObserver<T>) -> Bool {
    return lhs.hashValue == rhs.hashValue
}

public protocol ObservableProtocol {
    typealias ChangeType
    func observe(observer: (ChangeType) -> ()) -> (() -> ())!
}

public struct ValueChange<T> {
    public let old: T
    public let new: T
}

public final class Observable<T> : ObservableProtocol {
    public typealias ChangeType = ValueChange<T>
    public typealias Observer = (ChangeType) -> ()
    
    private var observers: Set<BoxedObserver<Observer>> = []
    public var value: T {
        didSet {
            evaluateChange(oldValue, new: value)
        }
    }
    
    public init(_ value: T) {
        self.value = value
    }
    
    func evaluateChange(old: T, new: T) {
        let change = ValueChange(old: old, new: new)
        observers.forEach { $0.closure(change) }
    }
    
    public func observe(observer: Observer) -> (() -> ())! {
        let boxed = BoxedObserver(observer)
        observers.insert(boxed)
        
        return { [weak self] in
            self?.observers.remove(boxed)
        }
    }
}

public enum CollectionChange<T: CollectionType> {
    case Added(T.Index)
    case Removed(T.Index)
    case Updated(T.Index)
}

public final class ObservableCollection<T: CollectionType where T.Generator.Element : Hashable> : ObservableProtocol {
    public typealias ChangeType = [CollectionChange<T>]
    public typealias Observer = (ChangeType) -> ()
    
    private var observers: Set<BoxedObserver<Observer>> = []
    public var values: T {
        get {
            return _values
        }
        set {
            let changes = evaluateChange(_values, new: newValue)
            _values = newValue
            if changes.count > 0 {
                observers.forEach { $0.closure(changes) }
            }
        }
    }
    
    private var _values : T
    
    public init(_ values: T) {
        _values = values
    }
    
    private func evaluateChange(old: T, new: T) -> [CollectionChange<T>] {
        let oldSet = Set(old)
        let newSet = Set(new)
        
        let added = newSet.subtract(oldSet)
        let removed = oldSet.subtract(newSet)
        let union = newSet.intersect(oldSet)
        
        let adds = added.map { (elem: T.Generator.Element) -> CollectionChange<T> in
            let idx = self._values.indexOf(elem)!
            return CollectionChange<T>.Added(idx)
        }
        
        let removes = removed.map { (elem: T.Generator.Element) -> CollectionChange<T> in
            let idx = old.indexOf(elem)!
            return CollectionChange<T>.Removed(idx)
        }
        
        let updates = union.flatMap { (elem: T.Generator.Element) -> CollectionChange<T>? in
            let idx = union.indexOf(elem)!
            let oldElem = oldSet[idx]
            let newElem = newSet[idx]
            if oldElem != newElem {
                let listIdx = self._values.indexOf(newElem)!
                return CollectionChange<T>.Updated(listIdx)
            } else {
                return nil
            }
        }
        
        return [adds, removes, updates].flatMap { $0 }
    }
    
    public func observe(observer: Observer) -> (() -> ())! {
        let boxed = BoxedObserver(observer)
        observers.insert(boxed)
        
        return { [weak self] in
            self?.observers.remove(boxed)
        }
    }
    
    public subscript (i: T.Index) -> T.Generator.Element? {
        get {
            return _values[i]
        }
    }
}

extension ObservableCollection where T : MutableCollectionType {
    public subscript (i: T.Index) -> T.Generator.Element {
        get {
            return _values[i]
        }
        
        set(newValue) {
            _values[i] = newValue
            observers.forEach { $0.closure([CollectionChange<T>.Updated(i)]) }
        }
    }
}

extension ObservableCollection where T : RangeReplaceableCollectionType {
    public func append(element: T.Generator.Element) {
        let change = CollectionChange<T>.Added(_values.endIndex)
        _values.append(element)
        observers.forEach { $0.closure([change]) }
    }
    
    public func append<S : SequenceType where S.Generator.Element == T.Generator.Element>(newElements: S) {
        let startIdx = _values.endIndex
        var count: T.Index.Distance = 0
        let changes = newElements.map { _ in
            return CollectionChange<T>.Added(startIdx.advancedBy(count++))
        }
        _values.appendContentsOf(newElements)
        observers.forEach { $0.closure(changes) }
    }
    
    public func insert(element: T.Generator.Element, atIndex i: T.Index) {
        let change = CollectionChange<T>.Added(i)
        _values.append(element)
        observers.forEach { $0.closure([change]) }
    }
    
    public func remove(i: T.Index) {
        let change = CollectionChange<T>.Removed(i)
        _values.removeAtIndex(i)
        observers.forEach { $0.closure([change]) }
    }
}

extension Observable : Copyable {
    public func copy() -> Observable {
        let copy = Observable(value)
        copy.observers = observers
        return copy
    }
}

extension ObservableCollection : Copyable {
    public func copy() -> ObservableCollection {
        let copy = ObservableCollection(_values)
        copy.observers = observers
        return copy
    }
}

public func ==<T: Equatable>(lhs: Observable<T>, rhs: Observable<T>) -> Bool {
    return lhs.value == rhs.value
}