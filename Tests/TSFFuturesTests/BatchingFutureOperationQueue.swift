//
//  Copyright © 2019-2021 Apple, Inc. All rights reserved.
//

import Atomics
import NIO
import NIOConcurrencyHelpers
import XCTest

@testable import TSFFutures

class BatchingFutureOperationQueueTests: XCTestCase {

    // Test dynamic capacity increase.
    func testDynamic() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }

        let manager = LLBOrderManager(on: group.next(), timeout: .seconds(5))

        var q = LLBBatchingFutureOperationQueue(name: "foo", group: group, maxConcurrentOperationCount: 1)

        let opsInFlight = ManagedAtomic(0)

        let future1: LLBFuture<Void> = q.execute { () -> LLBFuture<Void> in
            opsInFlight.wrappingIncrement(ordering: .relaxed)
            return manager.order(1).flatMap {
                manager.order(6) {
                    opsInFlight.wrappingDecrement(ordering: .relaxed)
                }
            }
        }

        let future2: LLBFuture<Void> = q.execute { () -> LLBFuture<Void> in
            opsInFlight.wrappingIncrement(ordering: .relaxed)
            return manager.order(3).flatMap {
                manager.order(6) {
                    opsInFlight.wrappingDecrement(ordering: .relaxed)
                }
            }
        }

        // Wait until future1 adss to opsInFlight.
        try manager.order(2).wait()
        XCTAssertEqual(opsInFlight.load(ordering: .relaxed), 1)

        // The test breaks without this line.
        q.maxOpCount += 1

        try manager.order(4).wait()
        XCTAssertEqual(opsInFlight.load(ordering: .relaxed), 2)
        try manager.order(5).wait()

        try manager.order(7).wait()
        XCTAssertEqual(opsInFlight.load(ordering: .relaxed), 0)

        try future2.wait()
        try future1.wait()

    }

    // Test if OpCount is correctly computed
    func testOpCount() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }

        let queue = LLBBatchingFutureOperationQueue(name: "foo", group: group, maxConcurrentOperationCount: 1)
        XCTAssertEqual(queue.opCount, 0)

        let fut = queue.execute { () -> LLBFuture<Void> in
            XCTAssertEqual(queue.opCount, 1)
            return group.any().makeSucceededVoidFuture().map {
                XCTAssertEqual(queue.opCount, 1)
            }
        }
        try fut.wait()
        XCTAssertEqual(queue.opCount, 0)
    }

    // Ensure execution is limited
    func testConcurrencyLimit() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }

        let queue = LLBBatchingFutureOperationQueue(name: "foo", group: group, maxConcurrentOperationCount: 1)

        let manager = LLBOrderManager(on: group.next(), timeout: .seconds(1))

        let fut1 = queue.execute { () -> LLBFuture<Void> in
            return manager.order(1).flatMap {
                manager.order(3)
            }
        }

        let fut2 = queue.execute { () -> LLBFuture<Void> in
            return manager.order(2)
        }

        // Because fut1 is stuck, fut2 won't execute
        XCTAssertThrowsError(try manager.order(4).wait())

        try? fut1.wait()
        try? fut2.wait()
    }

    // Ensure concurrent execution
    func testConcurrentExecution() throws {

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }

        // Max = 1 to fail test
        let queue = LLBBatchingFutureOperationQueue(name: "foo", group: group, maxConcurrentOperationCount: 2)

        let manager = LLBOrderManager(on: group.next(), timeout: .seconds(5))

        let fut1 = queue.execute { () -> LLBFuture<Void> in
            return manager.order(1).flatMap {
                manager.order(3)
            }
        }

        let fut2 = queue.execute { () -> LLBFuture<Void> in
            return manager.order(2)
        }

        // fut1 is stuck, fut2 should be executed concurrently else, this will fail
        try manager.order(4).wait()

        try fut1.wait()
        try fut2.wait()
    }

    // Test no execution for tasks enqueued after zero capacity
    func testZeroCapacity() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }

        var queue = LLBBatchingFutureOperationQueue(name: "foo", group: group, maxConcurrentOperationCount: 0)

        let manager = LLBOrderManager(on: group.next(), timeout: .seconds(1))

        let fut1 = queue.execute { () -> LLBFuture<Void> in
            return manager.order(1)
        }

        // Because fut1 is stuck and order 2 timesout
        XCTAssertThrowsError(try manager.order(2).wait())

        // Comment this line to break the test
        queue.maxOpCount = 1

        try manager.order(2).wait()

        try fut1.wait()
    }

    // Test setMaxOpCount on immutable queue.
    func testSetMaxConcurrency() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }

        let q = LLBBatchingFutureOperationQueue(name: "foo", group: group, maxConcurrentOperationCount: 1)
        q.setMaxOpCount(q.maxOpCount + 1)
        XCTAssertEqual(q.maxOpCount, 2)
    }

}
