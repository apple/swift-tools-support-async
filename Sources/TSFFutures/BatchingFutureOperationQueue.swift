// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Dispatch
import Foundation
import NIO
import NIOConcurrencyHelpers
import TSCUtility

/// Run the given computations on a given array in batches, exercising
/// a specified amount of parallelism.
///
/// - Discussion:
///     For some blocking operations (such as file system accesses) executing
///     them on the NIO loops is very expensive since it blocks the event
///     processing machinery. Here we use extra threads for such operations.
public struct LLBBatchingFutureOperationQueue {

    /// Threads capable of running futures.
    public let group: LLBFuturesDispatchGroup

    /// Whether the queue is suspended.
    @available(*, deprecated, message: "Property 'isSuspended' is deprecated.")
    public var isSuspended: Bool {
        // Cannot suspend a DispatchQueue
        false
    }

    /// Because `LLBBatchingFutureOperationQueue` is a struct, the compiler
    /// will claim that `maxOpCount`'s setter is `mutating`, even though
    /// `OperationQueue` is a threadsafe class.
    /// This method exists as a workaround to adjust the underlying concurrency
    /// of the operation queue without unnecessary synchronization.
    public func setMaxOpCount(_ maxOpCount: Int) {
        concurrencyLimiter.maximumConcurrency = Self.bridged(maxOpCount: maxOpCount)
    }

    /// Maximum number of operations executed concurrently.
    public var maxOpCount: Int {
        get { concurrencyLimiter.maximumConcurrency }
        set { self.setMaxOpCount(newValue) }
    }

    /// Return the number of operations currently queued.
    public var opCount: Int { concurrencyLimiter.sharesInUse }

    /// Name to be used for dispatch queue
    private let name: String

    /// QoS passed to DispatchQueue
    private let qos: DispatchQoS

    /// Lock protecting state.
    private let lock = NIOConcurrencyHelpers.Lock()

    /// Limits number of concurrent operations being executed
    private let concurrencyLimiter: ConcurrencyLimiter

    /// The queue of operations to run.
    private var workQueue = NIO.CircularBuffer<DispatchWorkItem>()

    @available(*, deprecated, message: "'qualityOfService' is deprecated: Use 'dispatchQoS'")
    public init(
        name: String, group: LLBFuturesDispatchGroup, maxConcurrentOperationCount maxOpCount: Int,
        qualityOfService: QualityOfService
    ) {
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
    public init(name: String, group: LLBFuturesDispatchGroup, maxConcurrentOperationCount maxOpCount: Int) {
        self.init(name: name, group: group, maxConcurrentOperationCount: maxOpCount, dispatchQoS: .default)
    }

    public init(
        name: String, group: LLBFuturesDispatchGroup, maxConcurrentOperationCount maxOpCnt: Int,
        dispatchQoS: DispatchQoS
    ) {
        self.group = group
        self.name = name
        self.qos = dispatchQoS

        self.concurrencyLimiter = ConcurrencyLimiter(maximumConcurrency: Self.bridged(maxOpCount: maxOpCnt))
    }

    public func execute<T>(_ body: @escaping () throws -> T) -> LLBFuture<T> {
        return self.concurrencyLimiter.withReplenishableLimit(eventLoop: group.any()) { eventLoop in
            let promise = eventLoop.makePromise(of: T.self)

            DispatchQueue(label: self.name, qos: self.qos).async {
                promise.fulfill(body)
            }

            return promise.futureResult
        }
    }

    // Deprecated: If we want to limit concurrency on EventLoopThreads, use FutureOperationQueue instead.
    // A future returning body is expected to not block.
    @available(*, deprecated, message: "Use FutureOperationQueue instead.")
    public func execute<T>(_ body: @escaping () -> LLBFuture<T>) -> LLBFuture<T> {
        return self.concurrencyLimiter.withReplenishableLimit(eventLoop: group.any()) { eventLoop in
            let promise = eventLoop.makePromise(of: T.self)

            DispatchQueue(label: self.name, qos: self.qos).async {
                body().cascade(to: promise)
            }

            return promise.futureResult
        }
    }

    /// Order-preserving parallel execution. Wait for everything to complete.
    @inlinable
    public func execute<A, T>(_ args: [A], minStride: Int = 1, _ body: @escaping (ArraySlice<A>) throws -> [T])
        -> LLBFuture<[T]>
    {
        let futures: [LLBFuture<[T]>] = executeNoWait(args, minStride: minStride, body)
        let loop = futures.first?.eventLoop ?? group.next()
        return LLBFuture<[T]>.whenAllSucceed(futures, on: loop).map { $0.flatMap { $0 } }
    }

    /// Order-preserving parallel execution.
    /// Do not wait for all executions to complete, returning individual futures.
    @inlinable
    public func executeNoWait<A, T>(
        _ args: [A], minStride: Int = 1, maxStride: Int = Int.max, _ body: @escaping (ArraySlice<A>) throws -> [T]
    ) -> [LLBFuture<[T]>] {
        let batches: [ArraySlice<A>] = args.tsc_sliceBy(
            maxStride: max(minStride, min(maxStride, args.count / maxOpCount)))
        return batches.map { arg in execute { try body(arg) } }
    }

    private static func bridged(maxOpCount: Int) -> Int {
        if maxOpCount < 0 {
            precondition(maxOpCount == OperationQueue.defaultMaxConcurrentOperationCount)
            return System.coreCount
        }
        return maxOpCount
    }
}
