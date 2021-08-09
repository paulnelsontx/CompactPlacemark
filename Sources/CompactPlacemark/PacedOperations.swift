//
//  PacedOperations.swift
//  Gas Tripper
//
//  Created by Paul Nelson on 8/6/21.
//  Copyright © 2021 Paul W. Nelson, Nelson Logic. All rights reserved.
//

import Foundation
import os.signpost

protocol PacedOperationProtocol {
    func pacedPerform(op: PacedOperation)
}

class PacedOperationQueue {
    var paceMicroseconds : UInt32 = 30010000
    var paceCount = 25

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
        }
    }
    public func complete() {
        os_signpost(.end, log:PacedOperationQueue.oslog, name: "perform", signpostID:self.signpostID)
        self.isFinished = true
    }
    override public func cancel() {
        os_signpost(.event, log:PacedOperationQueue.oslog, name: "cancel", signpostID:self.signpostID)
        isFinished = true
    }
    override public func start() {
        os_signpost(.begin, log:PacedOperationQueue.oslog, name: "perform", signpostID:self.signpostID)
        if delayMultiplier > 0 {
            usleep(100000 * delayMultiplier)
        }
        paced.pacedPerform(op:self)
    }
}
