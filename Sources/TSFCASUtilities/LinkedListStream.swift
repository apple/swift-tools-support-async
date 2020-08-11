// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import TSCUtility
import TSFCAS

/// Basic writer implementation that resembles a linked list where each node contains control data (like the channel)
/// and refs[0] always points to the dataID of the data chunk and refs[1] has the data ID for the next node in the
/// chain, if it's not the last node. This implementation is not thread safe.
public struct LLBLinkedListStreamWriter: LLBCASStreamWriter {
    private let db: LLBCASDatabase

    public private(set) var latestID: LLBFuture<LLBDataID>?

    public init(_ db: LLBCASDatabase) {
        self.db = db
    }

    @discardableResult
    public mutating func append(data: LLBByteBuffer, channel: UInt8, _ ctx: Context) -> LLBFuture<LLBDataID> {
        let latest = (
            // Append on the previously cached node, or use nil as sentinel if this is the first write.
            latestID?.map { $0 } ?? db.group.next().makeSucceededFuture(nil)
        ).flatMap { [db] (currentDataID: LLBDataID?) -> LLBFuture<LLBDataID> in
            db.put(data: data, ctx).flatMap { [db] contentID in
                // Put the channel as the only byte in the control node.
                let controlData = LLBByteBuffer.init(bytes: [channel])
                // compactmap to remove the currentDataID in case it was the nil sentinel.
                let refs: [LLBDataID] = [contentID, currentDataID].compactMap { $0 }
                return db.put(refs: refs, data: controlData, ctx)
            }
        }

        self.latestID = latest
        return latest
    }
}

public struct LLBLinkedListStreamReader: LLBCASStreamReader {
    private let db: LLBCASDatabase

    public init(_ db: LLBCASDatabase) {
        self.db = db
    }

    public func read(
        id: LLBDataID,
        channels: [UInt8]?,
        lastReadID: LLBDataID?,
        _ ctx: Context,
        readBlock: @escaping (UInt8, LLBByteBuffer) -> Bool
    ) throws -> LLBFuture<Void> {
        return innerRead(id: id, channels: channels, lastReadID: lastReadID, ctx, readBlock: readBlock).map { _ in () }
    }

    private func innerRead(
        id: LLBDataID,
        channels: [UInt8]? = nil,
        lastReadID: LLBDataID? = nil,
        _ ctx: Context,
        readBlock: @escaping (UInt8, LLBByteBuffer) throws -> Bool
    ) -> LLBFuture<Bool> {
        if id == lastReadID {
            return db.group.next().makeSucceededFuture(true)
        }

        return db.get(id, ctx).flatMap { node -> LLBFuture<Bool> in
            guard let node = node, let channel = node.data.getBytes(at: 0, length: 1)?[0] else {
                return db.group.next().makeFailedFuture(LLBCASStreamError.invalid)
            }

            let readChainFuture: LLBFuture<Bool>
            // If there are 2 refs, it's an intermediate node in the linked list, so we schedule a read of the next
            // node before scheduling a read of the current node.
            if node.refs.count == 2 {
                readChainFuture = innerRead(
                    id: node.refs[1],
                    channels: channels,
                    lastReadID: lastReadID,
                    ctx, readBlock: readBlock
                )
            } else {
                // If this is the last node, schedule a sentinel read that returns to keep on reading.
                readChainFuture = db.group.next().makeSucceededFuture(true)
            }

            return readChainFuture.flatMap { shouldContinue -> LLBFuture<Bool> in
                // If we don't want to continue reading, or if the channel is not requested, close the current chain
                // and propagate the desire to keep on reading.
                guard shouldContinue && channels?.contains(channel) ?? true else {
                    return db.group.next().makeSucceededFuture(shouldContinue)
                }

                // Read the node since it's expected to exist.
                return db.get(node.refs[0], ctx).flatMapThrowing { (dataNode: LLBCASObject?) -> Bool in
                    guard let dataNode = dataNode else {
                        throw LLBCASStreamError.missing
                    }

                    return try readBlock(channel, dataNode.data)
                }
            }
        }
    }
}
