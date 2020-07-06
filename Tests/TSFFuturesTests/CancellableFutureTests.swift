//
//  Copyright © 2019-2020 Apple, Inc. All rights reserved.
//

import XCTest

import NIO
import NIOConcurrencyHelpers

import TSFFutures

class CancellableFutureTests: XCTestCase {

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

    public enum GenericError: Swift.Error {
    case error
    }

    func testBasicSuccess() throws {
        let promise = group.next().makePromise(of: Void.self)
        let handler = Handler()
        let cf = LLBCancellableFuture(promise.futureResult, canceller: .init(handler))
        promise.succeed(())
        XCTAssertNoThrow(try promise.futureResult.wait())
        XCTAssertFalse(handler.wasCalled)
        cf.canceller.cancel(reason: #function)
        // Canceller won't be invoked if the future was already fired.
        XCTAssertFalse(handler.wasCalled)
    }

    func testBasicFailure() throws {
        let promise = group.next().makePromise(of: Void.self)
        let handler = Handler()
        let cf = LLBCancellableFuture(promise.futureResult, canceller: .init(handler))
        promise.fail(GenericError.error)
        XCTAssertThrowsError(try promise.futureResult.wait()) { error in
            XCTAssert(error is GenericError)
        }
        XCTAssertFalse(handler.wasCalled)
        cf.canceller.cancel(reason: #function)
        // Canceller won't be invoked if the future was already fired.
        XCTAssertFalse(handler.wasCalled)
    }

    func testBasicCancellation() throws {
        let promise = group.next().makePromise(of: Void.self)
        let handler = Handler()
        let cf = LLBCancellableFuture(promise.futureResult, canceller: .init(handler))
        cf.cancel(reason: #function)
        promise.succeed(())
        XCTAssertNoThrow(try promise.futureResult.wait())
        XCTAssertTrue(handler.wasCalled)
    }

    func testLateCancellation() throws {
        let promise = group.next().makePromise(of: Void.self)
        let handler = Handler()
        let cf = LLBCancellableFuture(promise.futureResult, canceller: .init(handler))
        promise.succeed(())
        XCTAssertNoThrow(try promise.futureResult.wait())
        cf.cancel(reason: #function)
        XCTAssertFalse(handler.wasCalled)
    }

    func testDoubleCancellation() throws {
        let promise = group.next().makePromise(of: Void.self)
        let handler = Handler()
        let cf = LLBCancellableFuture(promise.futureResult, canceller: .init(handler))
        cf.cancel(reason: #function)
        promise.succeed(())
        XCTAssertNoThrow(try promise.futureResult.wait())
        XCTAssertTrue(handler.wasCalled)
        cf.canceller.cancel(reason: #function)
        XCTAssertEqual(handler.timesCalled, 1)
    }

    func testLateInitialization() throws {
        let promise = group.next().makePromise(of: Void.self)
        let handler = Handler()
        let cf = LLBCancellableFuture(promise.futureResult)
        cf.cancel(reason: #function)
        // Setting the handler after cancelling.
        cf.canceller.set(handler: handler)
        promise.succeed(())
        XCTAssertNoThrow(try promise.futureResult.wait())
        XCTAssertTrue(handler.wasCalled)
        cf.canceller.cancel(reason: #function)
        XCTAssertEqual(handler.timesCalled, 1)
    }

    func testLateInitializationAndCancellation() throws {
        let promise = group.next().makePromise(of: Void.self)
        let handler = Handler()
        let cf = LLBCancellableFuture(promise.futureResult)
        promise.succeed(())
        XCTAssertNoThrow(try promise.futureResult.wait())
        // Setting the handler after cancelling.
        cf.canceller.set(handler: handler)
        cf.cancel(reason: #function)
        XCTAssertFalse(handler.wasCalled)
    }

}
