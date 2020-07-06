//
//  Copyright © 2019-2020 Apple, Inc. All rights reserved.
//

import XCTest

import NIO
import NIOConcurrencyHelpers

import TSFFutures


class FutureOperationQueueTests: XCTestCase {
    func testBasics() throws {
        let group = LLBMakeDefaultDispatchGroup()
        defer { try! group.syncShutdownGracefully() }

        let loop = group.next()
        let p1 = loop.makePromise(of: Bool.self)
        let p2 = loop.makePromise(of: Bool.self)
        let p3 = loop.makePromise(of: Bool.self)
        var p1Started = false
        var p2Started = false
        var p3Started = false

        let manager = LLBOrderManager(on: group.next())

        let q = LLBFutureOperationQueue(maxConcurrentOperations: 2)

        // Start the first two operations, they should run immediately.
        _ = q.enqueue(on: loop) { () -> LLBFuture<Bool> in
            p1Started = true
            return manager.order(2).flatMap {
                p1.futureResult
            }
        }
        _ = q.enqueue(on: loop) { () -> LLBFuture<Bool> in
            p2Started = true
            return manager.order(1).flatMap {
                p2.futureResult
            }
        }

        // Start the third, it should queue.
        _ = q.enqueue(on: loop) { () -> LLBFuture<Bool> in
            p3Started = true
            return manager.order(4).flatMap {
                p3.futureResult
            }
        }

        try manager.order(3).wait()
        XCTAssertEqual(p1Started, true)
        XCTAssertEqual(p2Started, true)
        XCTAssertEqual(p3Started, false)

        // Complete the first.
        p1.succeed(true)
        try manager.order(5).wait()

        // Now p3 should have started.
        XCTAssertEqual(p3Started, true)
        p2.succeed(true)
        p3.succeed(true)

        _ = try! p1.futureResult.wait()
        _ = try! p2.futureResult.wait()
        _ = try! p3.futureResult.wait()
    }

    // Stress test.
    func testStress() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer { try! group.syncShutdownGracefully() }

        let q = LLBFutureOperationQueue(maxConcurrentOperations: 2)
        
        let atomic = NIOAtomic.makeAtomic(value: 0)
        var futures: [LLBFuture<Bool>] = []
        let lock = NIOConcurrencyHelpers.Lock()
        DispatchQueue.concurrentPerform(iterations: 1_000) { i in
            let result = q.enqueue(on: group.next()) { () -> LLBFuture<Bool> in
                // Check that we aren't executing more operations than we would want.
                let p = group.next().makePromise(of: Bool.self)
                let prior = atomic.add(1)
                XCTAssert(prior >= 0 && prior < 2, "saw \(prior + 1) concurrent tasks at start")
                p.futureResult.whenComplete { _ in
                    let prior = atomic.add(-1)
                    XCTAssert(prior > 0 && prior <= 2, "saw \(prior) concurrent tasks at end")
                }

                // Complete the future at some point
                group.next().execute {
                    p.succeed(true)
                }
                
                return p.futureResult
            }
            
            lock.withLockVoid {
                futures.append(result)
            }
        }

        lock.withLockVoid {
            for future in futures {
                _ = try! future.wait()
            }
        }
    }
}
