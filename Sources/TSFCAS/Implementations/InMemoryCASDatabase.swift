// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Foundation

import NIOCore
import NIOConcurrencyHelpers

import TSCUtility
import TSFFutures
import TSFUtility


/// A simple in-memory implementation of the `LLBCASDatabase` protocol.
public final class LLBInMemoryCASDatabase: Sendable {
    struct State: Sendable {
        /// The content.
        var content = [LLBDataID: LLBCASObject]()

        var totalDataBytes: Int = 0
    }

    private let state: NIOLockedValueBox<State> = NIOLockedValueBox(State())

    /// Threads capable of running futures.
    public let group: LLBFuturesDispatchGroup

    /// The total number of data bytes in the database (this does not include the size of refs).
    public var totalDataBytes: Int {
        return self.state.withLockedValue { state in
            return state.totalDataBytes
        }
    }

    /// Create an in-memory database.
    public init(group: LLBFuturesDispatchGroup) {
        self.group = group
    }

    /// Delete the data in the database.
    /// Intentionally not exposed via the CASDatabase protocol.
    public func delete(_ id: LLBDataID, recursive: Bool) -> LLBFuture<Void> {
        self.state.withLockedValue { state in
            unsafeDelete(state: &state, id, recursive: recursive)
        }
        return group.next().makeSucceededFuture(())
    }
    private func unsafeDelete(state: inout State, _ id: LLBDataID, recursive: Bool) {
        guard let object = state.content[id] else {
            return
        }
        state.totalDataBytes -= object.data.readableBytes

        guard recursive else {
            return
        }

        for ref in object.refs {
            unsafeDelete(state: &state, ref, recursive: recursive)
        }
    }
}

extension LLBInMemoryCASDatabase: LLBCASDatabase {
    public func supportedFeatures() -> LLBFuture<LLBCASFeatures> {
        return group.next().makeSucceededFuture(LLBCASFeatures(preservesIDs: true))
    }

    public func contains(_ id: LLBDataID, _ ctx: Context) -> LLBFuture<Bool> {
        let result = self.state.withLockedValue { state in
            state.content.index(forKey: id) != nil
        }
        return group.next().makeSucceededFuture(result)
    }

    public func get(_ id: LLBDataID, _ ctx: Context) -> LLBFuture<LLBCASObject?> {
        let result = self.state.withLockedValue { state in state.content[id] }
        return group.next().makeSucceededFuture(result)
    }

    public func identify(refs: [LLBDataID] = [], data: LLBByteBuffer, _ ctx: Context) -> LLBFuture<LLBDataID> {
        return group.next().makeSucceededFuture(LLBDataID(blake3hash: data, refs: refs))
    }

    public func put(refs: [LLBDataID] = [], data: LLBByteBuffer, _ ctx: Context) -> LLBFuture<LLBDataID> {
        return put(knownID: LLBDataID(blake3hash: data, refs: refs), refs: refs, data: data, ctx)
    }

    public func put(knownID id: LLBDataID, refs: [LLBDataID] = [], data: LLBByteBuffer, _ ctx: Context) -> LLBFuture<LLBDataID> {
        self.state.withLockedValue { state in
            guard state.content[id] == nil else {
                assert(state.content[id]?.data == data, "put data for id doesn't match")
                return
            }
            state.totalDataBytes += data.readableBytes
            state.content[id] = LLBCASObject(refs: refs, data: data)
        }
        return group.next().makeSucceededFuture(id)
    }
}

public struct LLBInMemoryCASDatabaseScheme: LLBCASDatabaseScheme {
    public static let scheme = "mem"

    public static func isValid(host: String?, port: Int?, path: String, query: String?) -> Bool {
        return host == nil && port == nil && path == "" && query == nil
    }

    public static func open(group: LLBFuturesDispatchGroup, url: Foundation.URL) throws -> LLBCASDatabase {
        return LLBInMemoryCASDatabase(group: group)
    }
}
