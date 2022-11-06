//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import NIO
import NIOConcurrencyHelpers

internal final class ConcurrencyLimiter {
    public var maximumConcurrency: Int {
        get { lock.withLock { maximumConcurrency_ } }
        set {
            var waiters: [Waiter] = []
            lock.withLockVoid {
                let differenceInCapacity = (newValue - maximumConcurrency_)
                unitsLeft += differenceInCapacity
                maximumConcurrency_ = newValue
                waiters = tryFulfillSomeLocked()
            }
            waiters.fulfillWaiters()
        }
    }
    public var sharesInUse: Int { lock.withLock { maximumConcurrency_ - unitsLeft } }

    private var unitsLeft: Int  // protected by `self.lock`
    private var waiters: CircularBuffer<Waiter> = []  // protected by `self.lock`
    private let lock = Lock()
    private var maximumConcurrency_: Int  // protected by `self.lock`

    public init(maximumConcurrency: Int) {
        precondition(maximumConcurrency >= 0)

        self.maximumConcurrency_ = maximumConcurrency
        self.unitsLeft = maximumConcurrency
    }

    /// Reserves 1 unit of concurrency, executes body after which it restores the 1 unit.
    public func withReplenishableLimit<T>(
        eventLoop: EventLoop,
        _ body: @escaping (EventLoop) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        return self.withdraw(eventLoop: eventLoop).flatMap { lease in
            body(eventLoop).always { _ in
                self.replenish(lease)
            }
        }
    }

    private func tryFulfillSomeLocked() -> [Waiter] {
        var toSucceed: [Waiter] = []
        let unitsLeftAtStart = self.unitsLeft

        while !self.waiters.isEmpty, self.unitsLeft >= 1 {
            let waiter = self.waiters.removeFirst()

            self.unitsLeft -= 1
            assert(self.unitsLeft >= 0)
            toSucceed.append(waiter)
        }

        assert(unitsLeftAtStart - toSucceed.count == self.unitsLeft)
        return toSucceed
    }

    private func replenish(_ lease: Lease) {
        self.lock.withLock { () -> [Waiter] in
            self.unitsLeft += 1
            assert(self.unitsLeft <= self.maximumConcurrency_)
            return self.tryFulfillSomeLocked()
        }.fulfillWaiters()
    }

    /// Reserve 1 unit of the limit if available
    private func withdraw(eventLoop: EventLoop) -> EventLoopFuture<Lease> {
        let future = self.lock.withLock { () -> EventLoopFuture<Lease> in
            if self.waiters.isEmpty && self.unitsLeft >= 1 {
                self.unitsLeft -= 1

                return eventLoop.makeSucceededFuture(Lease())
            }

            let promise = eventLoop.makePromise(of: Lease.self)
            self.waiters.append(Waiter(promise: promise))

            return promise.futureResult
        }

        return future
    }

    fileprivate struct Waiter {
        var promise: EventLoopPromise<Lease>
    }

    fileprivate struct Lease {}
}

extension Array where Element == ConcurrencyLimiter.Waiter {
    fileprivate func fulfillWaiters() {
        self.forEach { waiter in
            return waiter.promise.succeed(.init())
        }
    }
}
