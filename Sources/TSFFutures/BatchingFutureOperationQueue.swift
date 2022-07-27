// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Dispatch
import Foundation
import NIOConcurrencyHelpers
import NIO

import TSCUtility


/// Run the given computations on a given array in batches, exercising
/// a specified amount of parallelism.
///
/// - Discussion:
///     For some blocking operations (such as file system accesses) executing
///     them on the NIO loops is very expensive since it blocks the event
///     processing machinery. Here we use extra threads for such operations.
public class LLBBatchingFutureOperationQueue {

    /// Threads capable of running futures.
    public let group: LLBFuturesDispatchGroup

    /// Whether the queue is suspended.
    @available(*, deprecated, message: "Property 'isSuspended' is deprecated.")
    public var isSuspended: Bool {
        // Cannot suspend a DispatchQueue
        false
    }

    /// Maximum number of operations executed concurrently.
    public var maxOpCount: Int {
        get { lock.withLock { maxOpCount_ } }
        set { scheduleMoreTasks { maxOpCount_ = newValue } }
    }

    /// Return the number of operations currently queued.
    public var opCount: Int { lock.withLock { opCount_ } }

    /// Queue of outstanding operations
    private let dispatchQueue: DispatchQueue

    /// Lock protecting state.
    private let lock = NIOConcurrencyHelpers.Lock()

    private var maxOpCount_: Int

    private var opCount_: Int

    /// The queue of operations to run.
    private var workQueue = NIO.CircularBuffer<DispatchWorkItem>()

    @available(*, deprecated, message: "'qualityOfService' is deprecated: Use 'dispatchQoS'")
    public convenience init(name: String, group: LLBFuturesDispatchGroup, maxConcurrentOperationCount maxOpCount: Int, qualityOfService: QualityOfService) {
        let dispatchQoS: DispatchQoS

        switch qualityOfService {
        case .userInteractive:
            dispatchQoS = .userInteractive
        case .userInitiated:
            dispatchQoS = .userInitiated
        case .utility:
            dispatchQoS = .utility
        case .background:
            dispatchQoS = .background
        default:
            dispatchQoS = .default
        }

        self.init(name: name, group: group, maxConcurrentOperationCount: maxOpCount, dispatchQoS: dispatchQoS)
    }

    ///
    /// - Parameters:
    ///    - name:      Unique string label, for logging.
    ///    - group:     Threads capable of running futures.
    ///    - maxConcurrentOperationCount:
    ///                 Operations to execute in parallel.
    public convenience init(name: String, group: LLBFuturesDispatchGroup, maxConcurrentOperationCount maxOpCount: Int) {
        self.init(name: name, group: group, maxConcurrentOperationCount: maxOpCount, dispatchQoS: .default)
    }

    public init(name: String, group: LLBFuturesDispatchGroup, maxConcurrentOperationCount maxOpCnt: Int, dispatchQoS: DispatchQoS) {
        self.group = group
        self.dispatchQueue = DispatchQueue(label: name, qos: dispatchQoS, attributes: .concurrent)
        self.opCount_ = 0
        self.maxOpCount_ = maxOpCnt
    }

    public func execute<T>(_ body: @escaping () throws -> T) -> LLBFuture<T> {
        let promise = group.any().makePromise(of: T.self)

        let workItem = DispatchWorkItem {
            promise.fulfill(body)
            self.scheduleMoreTasks {
                self.opCount_ -= 1
            }
        }

        self.scheduleMoreTasks {
            workQueue.append(workItem)
        }

        return promise.futureResult
    }

    public func execute<T>(_ body: @escaping () -> LLBFuture<T>) -> LLBFuture<T> {
        let promise = group.any().makePromise(of: T.self)

        let workItem = DispatchWorkItem {
            let f = body()
            f.cascade(to: promise)

            _ = try? f.wait()

            self.scheduleMoreTasks {
                self.opCount_ -= 1
            }
        }

        self.scheduleMoreTasks {
            workQueue.append(workItem)
        }

        return promise.futureResult
    }

    /// Order-preserving parallel execution. Wait for everything to complete.
    @inlinable
    public func execute<A,T>(_ args: [A], minStride: Int = 1, _ body: @escaping (ArraySlice<A>) throws -> [T]) -> LLBFuture<[T]> {
        let futures: [LLBFuture<[T]>] = executeNoWait(args, minStride: minStride, body)
        let loop = futures.first?.eventLoop ?? group.next()
        return LLBFuture<[T]>.whenAllSucceed(futures, on: loop).map{$0.flatMap{$0}}
    }

    /// Order-preserving parallel execution.
    /// Do not wait for all executions to complete, returning individual futures.
    @inlinable
    public func executeNoWait<A,T>(_ args: [A], minStride: Int = 1, maxStride: Int = Int.max, _ body: @escaping (ArraySlice<A>) throws -> [T]) -> [LLBFuture<[T]>] {
        let batches: [ArraySlice<A>] = args.tsc_sliceBy(maxStride: max(minStride, min(maxStride, args.count / maxOpCount)))
        return batches.map{arg in execute{try body(arg)}}
    }

    private func scheduleMoreTasks(performUnderLock: () -> Void) {
        let toExecute: [DispatchWorkItem] = lock.withLock {
            performUnderLock()

            var scheduleItems: [DispatchWorkItem] = []

            while opCount_ < maxOpCount_ {

                // Schedule a new operation, if available.
                guard let op = workQueue.popFirst() else {
                    break
                }

                self.opCount_ += 1
                scheduleItems.append(op)
            }

            return scheduleItems
        }

        for workItem in toExecute {
            dispatchQueue.async(execute: workItem)
        }
    }

}
