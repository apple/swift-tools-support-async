// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import TSCUtility
import TSFCAS
import TSFCASFileTree

/// Implements the reading logic to read any kind of streaming data storage implemented. Currently it's hardcoded to
/// read the LinkedList stream contents, but could get extended in the future when new storage structures are
/// implemented. This should be the unified API to read streaming content, so that readers do not need to understand
/// which writer was used to store the data.
public struct LLBCASStreamReader {
    private let db: LLBCASDatabase

    public init(_ db: LLBCASDatabase) {
        self.db = db
    }

    public func read(
        id: LLBDataID,
        channels: [UInt8]?,
        lastReadID: LLBDataID?,
        _ ctx: Context,
        readerBlock: @escaping (UInt8, LLBByteBufferView) throws -> Bool
    ) -> LLBFuture<Void> {
        return innerRead(
            id: id,
            channels: channels,
            lastReadID: lastReadID,
            ctx,
            readerBlock: readerBlock
        ).map { _ in () }
    }

    private func innerRead(
        id: LLBDataID,
        channels: [UInt8]? = nil,
        lastReadID: LLBDataID? = nil,
        _ ctx: Context,
        readerBlock: @escaping (UInt8, LLBByteBufferView) throws -> Bool
    ) -> LLBFuture<Bool> {
        if id == lastReadID {
            return db.group.next().makeSucceededFuture(true)
        }

        return LLBCASFSClient(db).load(id, ctx).flatMap { node in
            guard let tree = node.tree else {
                return self.db.group.next().makeFailedFuture(LLBCASStreamError.invalid)
            }

            let readChainFuture: LLBFuture<Bool>

            // If there is a "prev" directory, treat this as a linked list implementation. This is an implementation
            // detail that could be cleaned up later, but the idea is that there's a single unified reader entity.
            if let (id, _) = tree.lookup("prev") {
                readChainFuture = self.innerRead(
                    id: id,
                    channels: channels,
                    lastReadID: lastReadID,
                    ctx,
                    readerBlock: readerBlock
                )
            } else {
                // If this is the last node, schedule a sentinel read that returns to keep on reading.
                readChainFuture = self.db.group.next().makeSucceededFuture(true)
            }

            return readChainFuture.flatMap { shouldContinue -> LLBFuture<Bool> in
                // If we don't want to continue reading, or if the channel is not requested, close the current chain
                // and propagate the desire to keep on reading.
                guard shouldContinue else {
                    return self.db.group.next().makeSucceededFuture(shouldContinue)
                }

                let files = tree.files.filter {
                    $0.type == .plainFile
                }

                guard files.count == 1, let (contentID, _) = tree.lookup(files[0].name) else {
                    return self.db.group.next().makeFailedFuture(LLBCASStreamError.invalid)
                }

                let channelOpt = files.first.flatMap { $0.name.split(separator: ".").first }.flatMap { UInt8($0) }

                guard let channel = channelOpt,
                      channels?.contains(channel) ?? true else {
                    return self.db.group.next().makeSucceededFuture(true)
                }

                return LLBCASFSClient(self.db).load(contentID, ctx).flatMap { node in
                    guard let blob = node.blob else {
                        return self.db.group.next().makeFailedFuture(LLBCASStreamError.missing)
                    }

                    return blob.read(ctx).flatMapThrowing { byteBufferView in
                        return try readerBlock(channel, byteBufferView)
                    }
                }
            }
        }
    }
}

// Convenience extension for default parameters.
public extension LLBCASStreamReader {
    @inlinable
    func read(
        id: LLBDataID,
        _ ctx: Context,
        readerBlock: @escaping (UInt8, LLBByteBufferView) throws -> Bool
    ) -> LLBFuture<Void> {
        return read(id: id, channels: nil, lastReadID: nil, ctx, readerBlock: readerBlock)
    }

    @inlinable
    func read(
        id: LLBDataID,
        channels: [UInt8],
        _ ctx: Context,
        readerBlock: @escaping (UInt8, LLBByteBufferView) throws -> Bool
    ) -> LLBFuture<Void> {
        return read(id: id, channels: channels, lastReadID: nil, ctx, readerBlock: readerBlock)
    }

    @inlinable
    func read(
        id: LLBDataID,
        lastReadID: LLBDataID,
        _ ctx: Context,
        readerBlock: @escaping (UInt8, LLBByteBufferView) throws -> Bool
    ) -> LLBFuture<Void> {
        return read(id: id, channels: nil, lastReadID: lastReadID, ctx, readerBlock: readerBlock)
    }
}

/// Common error types for stream protocol implementations.
public enum LLBCASStreamError: Error {
    case invalid
    case missing
}
