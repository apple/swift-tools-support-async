//
//  Copyright © 2019-2021 Apple, Inc. All rights reserved.
//

import Atomics
import XCTest

import NIO
import NIOConcurrencyHelpers

import TSFFutures


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

}
