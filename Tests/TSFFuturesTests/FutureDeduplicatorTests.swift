//
//  Copyright © 2019 Apple, Inc. All rights reserved.
//

import XCTest

import NIO

import TSFFutures


class FutureDeduplicatorTests: XCTestCase {

    var group: LLBFuturesDispatchGroup!

    override func setUp() {
        super.setUp()

        group = LLBMakeDefaultDispatchGroup()
    }

    override func tearDown() {
        super.tearDown()

        try! group.syncShutdownGracefully()
        group = nil
    }

    /// Test that we don't re-resolve the cached value
    func testSerialCoalescing() throws {
        let cache = LLBFutureDeduplicator<Int, String>(group: group)
        var hits = 0

        let v1Future = cache.value(for: 1) { key in
            hits += 1
            return group.next().makeSucceededFuture("\(hits)")
        }

        let v1 = try v1Future.wait()

        let v2Future = cache.value(for: 1) { key in
            hits += 1
            return group.next().makeSucceededFuture("\(hits)")
        }

        let v2 = try v2Future.wait()

        XCTAssertEqual(hits, 2)
        XCTAssertNotEqual(v1, v2)
    }

    /// Test that we don't re-resolve even if resolution takes time.
    func testParallelCoalescing() throws {
        let cache = LLBFutureDeduplicator<Int, String>(group: group)
        var hits = 0

        func resolver(_ key: Int) -> LLBFuture<String> {
            hits += 1
            let promise = group.next().makePromise(of: String.self)
            _ = group.next().scheduleTask(in: TimeAmount.milliseconds(100)) {
                promise.succeed("\(hits)")
            }
            return promise.futureResult
        }

        let v1Future = cache.value(for: 1, with: resolver)
        let v2Future = cache.value(for: 1, with: resolver)

        XCTAssertEqual(try v1Future.wait(), try v2Future.wait())
        XCTAssertEqual(hits, 1)
    }

    /// Test that we don't re-resolve an in-flight value when requesting multiple
    func testMultipleValueResolution() throws {
        let cache = LLBFutureDeduplicator<Int, Int>(group: group)

        // Immediate resolution.
        _ = try cache.value(for: 0) { key in
            return group.next().makeSucceededFuture(0)
        }.wait()

        // Delayed resolution.
        _ = cache.value(for: 1) { key in
            let promise = group.next().makePromise(of: Int.self)
            _ = group.next().scheduleTask(in: TimeAmount.milliseconds(100)) {
                promise.succeed(key)
            }
            return promise.futureResult
        }

        let futures = cache.values(for: [0, 1, 2, 3]) { keys in
            // This has already been resolved once, so we are expected
            // to resolve it anew in the `FutureDeduplicator` abstraction.
            // See `EventualResultsCache` for a different behavior.
            XCTAssertTrue(keys.contains(0), "Unexpected resolver invocation")
            XCTAssertFalse(keys.contains(1), "Unexpected resolver invocation")
            XCTAssertTrue(keys.contains(2), "Unexpected resolver invocation")
            XCTAssertTrue(keys.contains(3), "Unexpected resolver invocation")
            return group.next().makeSucceededFuture(keys)
        }

        let results = try LLBFuture.whenAllSucceed(futures, on: group.next()).wait()

        XCTAssertEqual([0, 1, 2, 3], results)
    }

}
