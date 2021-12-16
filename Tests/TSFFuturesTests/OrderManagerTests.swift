//
//  Copyright © 2020 Apple, Inc. All rights reserved.
//

import XCTest

import NIO

import TSFFutures

class OrderManagerTests: XCTestCase {

    func testOrderManagerWithLoop() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            try! group.syncShutdownGracefully()
        }
        do {
            let manager = LLBOrderManager(on: group.next())
            try manager.reset().wait()
        }
    }

}

