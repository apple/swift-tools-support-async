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

private extension String {
    func prepending(_ prefix: String) -> String {
        return prefix + self
    }
}

/// Basic writer implementation that resembles a linked list where each node contains control data (like the channel)
/// and refs[0] always points to the dataID of the data chunk and refs[1] has the data ID for the next node in the
/// chain, if it's not the last node. This implementation is not thread safe.
public struct LLBLinkedListStreamWriter {
    private let db: LLBCASDatabase
    private let ext: String

    private var latestData: LLBFuture<(id: LLBDataID, aggregateSize: Int)>?

    public var latestID: LLBFuture<LLBDataID>? {
        latestData?.map { $0.id }
    }

    public init(_ db: LLBCASDatabase, ext: String? = nil) {
        self.db = db
        self.ext = ext?.prepending(".") ?? ""
    }

    // This rebases the current logs onto a new data ID, potentially losing all the previous uploads if not saved
    // previously. The newBase should be another dataID produced by a LLBLinkedListStreamWriter.
    public mutating func rebase(onto newBase: LLBDataID, _ ctx: Context) {
        self.latestData = LLBCASFSClient(db).load(newBase, ctx).map{
            $0.tree
        }.tsf_unwrapOptional(orStringError: "Expected an LLBCASTree").map { tree in
            (id: tree.id, aggregateSize: tree.aggregateSize)
        }
    }

    @discardableResult
    public mutating func append(data: LLBByteBuffer, channel: UInt8, _ ctx: Context) -> LLBFuture<LLBDataID> {
        let latestData = (
            // Append on the previously cached node, or use nil as sentinel if this is the first write.
            self.latestData?.map { $0 } ?? db.group.next().makeSucceededFuture(nil)
        ).flatMap { [db, ext] (previousData: (id: LLBDataID, aggregateSize: Int)?) -> LLBFuture<(id: LLBDataID, aggregateSize: Int)> in
            db.put(data: data, ctx).flatMap { [db, ext] contentID in

                var entries = [
                    LLBDirectoryEntryID(
                        info: .init(name: "\(channel)\(ext)", type: .plainFile, size: data.readableBytes),
                        id: contentID
                    ),
                ]

                let aggregateSize: Int
                if let (prevID, prevSize) = previousData {
                    entries.append(
                        LLBDirectoryEntryID(
                            info: .init(name: "prev", type: .directory, size: prevSize),
                            id: prevID
                        )
                    )
                    aggregateSize = prevSize + data.readableBytes
                } else {
                    aggregateSize = data.readableBytes
                }

                return LLBCASFileTree.create(files: entries, in: db, ctx).map { (id: $0.id, aggregateSize: aggregateSize) }
            }
        }

        self.latestData = latestData
        return latestData.map { $0.id }
    }
}

public extension LLBLinkedListStreamWriter {
    @discardableResult
    @inlinable
    mutating func append(data: LLBByteBuffer, _ ctx: Context) -> LLBFuture<LLBDataID> {
        return append(data: data, channel: 0, ctx)
    }
}
