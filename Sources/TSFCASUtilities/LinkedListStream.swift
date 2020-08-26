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

    public private(set) var latestID: LLBFuture<LLBDataID>?

    public init(_ db: LLBCASDatabase, ext: String? = nil) {
        self.db = db
        self.ext = ext?.prepending(".") ?? ""
    }

    @discardableResult
    public mutating func append(data: LLBByteBuffer, channel: UInt8, _ ctx: Context) -> LLBFuture<LLBDataID> {
        let latest = (
            // Append on the previously cached node, or use nil as sentinel if this is the first write.
            latestID?.map { $0 } ?? db.group.next().makeSucceededFuture(nil)
        ).flatMap { [db, ext] (currentDataID: LLBDataID?) -> LLBFuture<LLBDataID> in
            db.put(data: data, ctx).flatMap { [db, ext] contentID in

                var entries = [
                    LLBDirectoryEntryID(
                        info: .init(name: "\(channel)\(ext)", type: .plainFile, size: data.readableBytes),
                        id: contentID
                    ),
                ]

                if let currentDataID = currentDataID {
                    entries.append(
                        LLBDirectoryEntryID(
                            info: .init(name: "prev", type: .directory, size: 0),
                            id: currentDataID
                        )
                    )
                }
                return LLBCASFileTree.create(files: entries, in: db, ctx).map { $0.id }
            }
        }

        self.latestID = latest
        return latest
    }
}

public extension LLBLinkedListStreamWriter {
    @discardableResult
    @inlinable
    mutating func append(data: LLBByteBuffer, _ ctx: Context) -> LLBFuture<LLBDataID> {
        return append(data: data, channel: 0, ctx)
    }
}
