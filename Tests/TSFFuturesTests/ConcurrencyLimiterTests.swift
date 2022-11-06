//
//  Copyright © 2022 Apple, Inc. All rights reserved.
//

import NIO
import NIOConcurrencyHelpers
import XCTest

@testable import TSFFutures

class ConcurrencyLimiterTests: XCTestCase {
    private var eventLoop: EmbeddedEventLoop!

    func testConsumeAll() {
        let cl = ConcurrencyLimiter(maximumConcurrency: 5)
        XCTAssertNoThrow(
            try cl.withReplenishableLimit(eventLoop: self.eventLoop) { _ in
                cl.withReplenishableLimit(eventLoop: self.eventLoop) { _ in
                    cl.withReplenishableLimit(eventLoop: self.eventLoop) { _ in
                        cl.withReplenishableLimit(eventLoop: self.eventLoop) { _ in
                            cl.withReplenishableLimit(eventLoop: self.eventLoop) { _ in
                                self.eventLoop.makeSucceededFuture(())
                            }
                        }
                    }
                }
            }.wait())
    }

    func testZeroCapacityWorks() throws {
        let cl = ConcurrencyLimiter(maximumConcurrency: 0)

        let fut = cl.withReplenishableLimit(eventLoop: self.eventLoop) { _ in
            self.eventLoop.makeSucceededVoidFuture()
        }
        cl.maximumConcurrency = 1
        XCTAssertNoThrow(try fut.wait())
    }

    override func setUpWithError() throws {
        self.eventLoop = EmbeddedEventLoop()
    }

    override func tearDownWithError() throws {
        try self.eventLoop?.syncShutdownGracefully()
        self.eventLoop = nil
    }
}
