//
//  Copyright © 2019-2020 Apple, Inc. All rights reserved.
//

import XCTest

import NIO
import NIOConcurrencyHelpers

import TSFFutures

class CancellerTests: XCTestCase {

    var group: EventLoopGroup!

    override func setUp() {
        super.setUp()

        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    override func tearDown() {
        super.tearDown()

        try! group.syncShutdownGracefully()
        group = nil
    }

    /// This is a mock for some function that is able to cancel
    /// future's underlying operation.
    struct Handler: LLBCancelProtocol {
        private let called = NIOAtomic.makeAtomic(value: 0)

        var wasCalled: Bool {
            return timesCalled > 0
        }

        var timesCalled: Int {
            return called.load()
        }

        func cancel(reason: String?) {
            _ = called.add(1)
        }
    }

    func testCancel() throws {
        let handler = Handler()
        let canceller = LLBCanceller(handler)
        XCTAssertFalse(handler.wasCalled)
        canceller.cancel(reason: #function)
        XCTAssertTrue(handler.wasCalled)
    }

    func testDoubleCancellation() throws {
        let handler = Handler()
        let canceller = LLBCanceller(handler)
        canceller.cancel(reason: #function)
        XCTAssertTrue(handler.wasCalled)
        canceller.cancel(reason: #function)
        XCTAssertEqual(handler.timesCalled, 1)
    }

    func testLateInitialization() throws {
        let handler = Handler()
        let canceller = LLBCanceller()
        canceller.cancel(reason: #function)
        // Setting the handler after cancelling.
        canceller.set(handler: handler)
        XCTAssertTrue(handler.wasCalled)
        canceller.cancel(reason: #function)
        XCTAssertEqual(handler.timesCalled, 1)
    }

    func testAbandonFirst() throws {
        let handler = Handler()
        let canceller = LLBCanceller()
        canceller.abandon()
        canceller.cancel(reason: #function)
        canceller.set(handler: handler)
        XCTAssertFalse(handler.wasCalled)
    }

    func testAbandonLast() throws {
        let handler = Handler()
        let canceller = LLBCanceller()
        canceller.cancel(reason: #function)
        canceller.abandon()
        canceller.set(handler: handler)
        XCTAssertFalse(handler.wasCalled)
    }

}
