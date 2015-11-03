//
//  ClosureTimer.swift
//  ControllerKit
//
//  Created by Robin Goos on 26/10/15.
//  Copyright © 2015 Robin Goos. All rights reserved.
//

import Foundation

final class ClosureTimerProxy : NSObject {
    let callback: () -> ()
    let repeats: Bool
    
    init(callback: () -> (), repeats: Bool) {
        self.callback = callback
        self.repeats = repeats
    }
    
    func performCallback(timer: NSTimer) {
        if (timer.valid) {
            callback()
            if (!repeats) {
                timer.invalidate()
            }
        }
    }
}

public extension NSTimer {
    static func setTimeout(timeout: NSTimeInterval, repeats: Bool = false, callback: () -> ()) -> NSTimer {
        let proxy = ClosureTimerProxy(callback: callback, repeats: repeats)
        let timer = NSTimer(timeInterval: timeout, target: proxy, selector: "performCallback:", userInfo: nil, repeats: repeats)
        NSRunLoop.mainRunLoop().addTimer(timer, forMode: NSRunLoopCommonModes)
        return timer
    }
}