//
//  Dynamic.swift
//  WatchCommunicator
//
//  Created by Stephen O'Connor (MHP) on 01.09.21.
//

import Foundation

class Dynamic<Value> {
    
    typealias Listener = (Value) -> ()
    var listener: Listener?
    
    init(_ value: Value) {
        self.value = value
    }
    
    var value: Value {
        didSet {
            listener?(value)
        }
    }
    
    func bind(_ listener: Listener?) {
        self.listener = listener
    }
    
    func bindAndFire(_ listener: Listener?) {
        self.listener = listener
        listener?(value)
    }
}

/// Works just like `Dynamic` but will only notify if the value has changed according to the `Equatable` protocol.
class DynamicChange<Value: Equatable> {
    
    typealias Listener = (Value) -> ()
    var listener: Listener?
    
    init(_ value: Value) {
        self.value = value
    }
    
    var value: Value {
        didSet {
            if oldValue != self.value {
                listener?(value)
            }
        }
    }
    
    func bind(_ listener: Listener?) {
        self.listener = listener
    }
    
    func bindAndFire(_ listener: Listener?) {
        self.listener = listener
        listener?(value)
    }
    
    func fire() {
        listener?(value)
    }
}

