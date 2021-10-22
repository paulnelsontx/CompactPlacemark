//
//  PacedOperations.swift
//  Gas Tripper
//
//  Created by Paul Nelson on 8/6/21.
//  Copyright © 2021 Paul W. Nelson, Nelson Logic. All rights reserved.
//

import Foundation
import os.signpost
#if os(iOS)
import UIKit
#endif

protocol PacedOperationProtocol {
    func pacedPerform(op: PacedOperation)
}

class PacedOperationQueue {
//    var paceMicroseconds : UInt32 = 30010000
//    var paceCount = 25
    var paceMicroseconds : UInt32 = 5010000
    var paceCount = 5

    static private var _shared : PacedOperationQueue?
    static public var shared : PacedOperationQueue {
        if _shared == nil {
            _shared = PacedOperationQueue()
        }
        return _shared!
    }
    internal static var oslog = OSLog(subsystem: "com.nelsonlogic", category: "PacedOperationQueue")

    private var queue : OperationQueue
    private var addCount = 0
    private var signpostID : OSSignpostID = .exclusive

    init() {
        queue = OperationQueue()
        queue.qualityOfService = .background
        
        queue.name = "PacedOperationQueue"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .background
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil,
                                               queue: nil) { note in
            self.queue.isSuspended = true
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil,
                                               queue: nil) { note in
            self.queue.isSuspended = false
        }
    }
    
    func add(_ op: PacedOperation, delayMultiplier: UInt32 = 0) {
        addCount += 1
        signpostID = op.signpostID
        os_signpost(.event, log:PacedOperationQueue.oslog, name: "add", signpostID:op.signpostID)
        self.queue.addOperation(op)
        if addCount % paceCount == 0 {
            queue.addBarrierBlock {
                print("barrier \(self.queue.operationCount)")
                os_signpost(.begin, log:PacedOperationQueue.oslog, name: "barrier", signpostID:self.signpostID)
                usleep(self.paceMicroseconds)
                os_signpost(.end, log:PacedOperationQueue.oslog, name: "barrier", signpostID:self.signpostID)
                print("barrier done")
            }
        }
    }
}

class PacedOperation : Operation {
    private var delayMultiplier : UInt32 = 0
    private var paced : PacedOperationProtocol
    public var signpostID = OSSignpostID(log:PacedOperationQueue.oslog)
    #if os(iOS)
    private var backgroundID: UIBackgroundTaskIdentifier?
    #endif
    
    init( paced: PacedOperationProtocol, delayMultiplier : UInt32 = 0 ) {
        self.paced = paced
        self.delayMultiplier = delayMultiplier
        super.init()
        self.queuePriority = Operation.QueuePriority.normal
    }
    override var isAsynchronous: Bool {
        true
    }
    var _executing: Bool = false
    override var isExecuting: Bool {
        get { return _executing }
        set {
            if( _executing != newValue ) {
                willChangeValue(forKey: "isExecuting")
                _executing = newValue
                didChangeValue(forKey: "isExecuting")
            }
        }
    }
    var _finished : Bool = false
    override var isFinished: Bool {
        get { return _finished }
        set {
            if( _finished != newValue ) {
                willChangeValue(forKey: "isFinished")
                _finished = newValue
                if _finished {
                    isExecuting = false
                }
                didChangeValue(forKey: "isFinished")
            }
            #if os(iOS)
            if isFinished, let task = backgroundID {
                UIApplication.shared.endBackgroundTask(task)
            }
            #endif
        }
    }
    public func complete() {
        os_signpost(.end, log:PacedOperationQueue.oslog, name: "perform", signpostID:self.signpostID)
        if _executing {
            self.isExecuting = false
            self.isFinished = true
        }
    }
    override public func cancel() {
        self.isExecuting = false
        os_signpost(.event, log:PacedOperationQueue.oslog, name: "cancel", signpostID:self.signpostID)
        if _executing {
            self.isFinished = true
        }
    }
    override public func start() {
        #if os(iOS)
        self.backgroundID = UIApplication.shared.beginBackgroundTask {
            self.cancel()
        }
        #endif
        self.isExecuting = true
        os_signpost(.begin, log:PacedOperationQueue.oslog, name: "perform", signpostID:self.signpostID)
        if delayMultiplier > 0 {
            usleep(100000 * delayMultiplier)
        }
        paced.pacedPerform(op:self)
    }
}
