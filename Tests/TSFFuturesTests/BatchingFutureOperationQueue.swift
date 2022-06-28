//
//  Copyright © 2019-2021 Apple, Inc. All rights reserved.
//

import XCTest

import NIO
import NIOConcurrencyHelpers

import TSFFutures


class BatchingFutureOperationQueueTests: XCTestCase {
    
    func doDynamic(q: LLBBatchingFutureOperationQueue) throws {
        let manager = LLBOrderManager(on: q.group.next(), timeout: .seconds(5))

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

    // Test dynamic capacity increase.
    func testDynamicDeprecated() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }
        let q = LLBBatchingFutureOperationQueue(name: "foo", group: group, maxConcurrentOperationCount: 1)
        
        try doDynamic(q: q)
    }
    
    func testDynamic() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }
        let q = LLBBatchingFutureOperationQueue(name: "foo", group: group, maxConcurrentOperationCount: 1, dispatchQoS: .default)
        
        try doDynamic(q: q)
    }
}
