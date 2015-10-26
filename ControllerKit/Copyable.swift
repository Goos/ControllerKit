//
//  Copyable.swift
//  ControllerKit
//
//  Created by Robin Goos on 25/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

public protocol Copyable {
    func copy() -> Self
}