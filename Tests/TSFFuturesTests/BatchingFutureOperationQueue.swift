//
//  Copyright © 2019-2021 Apple, Inc. All rights reserved.
//

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

        let opsInFlight = NIOAtomic.makeAtomic(value: 0)

        let future1: LLBFuture<Void> = q.execute { () -> LLBFuture<Void> in
            _ = opsInFlight.add(1)
            return manager.order(1).flatMap {
                manager.order(6) {
                    _ = opsInFlight.add(-1)
                }
            }
        }

        let future2: LLBFuture<Void> = q.execute { () -> LLBFuture<Void> in
            _ = opsInFlight.add(1)
            return manager.order(3).flatMap {
                manager.order(6) {
                    _ = opsInFlight.add(-1)
                }
            }
        }

        // Wait until future1 adss to opsInFlight.
        try manager.order(2).wait()
        XCTAssertEqual(opsInFlight.load(), 1)

        // The test breaks without this line.
        q.maxOpCount += 1

        try manager.order(4).wait()
        XCTAssertEqual(opsInFlight.load(), 2)
        try manager.order(5).wait()

        try manager.order(7).wait()
        XCTAssertEqual(opsInFlight.load(), 0)

        try future2.wait()
        try future1.wait()

    }

}
