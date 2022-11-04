// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Atomics
import Foundation

import NIOConcurrencyHelpers
import TSCBasic
import TSCUtility

import TSFCAS


public enum LLBExportError: Error {
    /// The given id was referenced as a directory, but the object encoding didn't match expectations.
    case unexpectedDirectoryData(LLBDataID)

    /// The given id was referenced as a file, but the object encoding didn't match expectations.
    case unexpectedFileData(LLBDataID)

    /// The given id was referenced as a symlink, but the object encoding didn't match expectations.
    case unexpectedSymlinkData(LLBDataID)

    /// The given id was required, but is missing.
    case missingReference(LLBDataID)

    /// An unexpected error was thrown while communicating with the database.
    case unexpectedDatabaseError(Error)

    /// Formatting/protocol error.
    case formatError(reason: String)

    /// There was an error interacting with the filesystem.
    case ioError(Error)
}

public enum LLBExportIOError: Error {
    /// Export was unable to export the symbolic link to `path` (with the given `target`).
    case unableToSymlink(path: AbsolutePath, target: String)
    case unableSyscall(path: AbsolutePath, call: String, error: String)
    case fileTooLarge(path: AbsolutePath)
    case uncompressFailed(path: AbsolutePath)
}

public protocol LLBCASFileTreeExportProgressStats: AnyObject {
    var bytesDownloaded: Int { get }
    var bytesExported: Int { get }
    var bytesToExport: Int { get }
    var objectsExported: Int { get }
    var objectsToExport: Int { get }
    var downloadsInProgressObjects: Int { get }
    var debugDescription: String { get }
}

public extension LLBCASFileTree {

    final class ExportProgressStats: LLBCASFileTreeExportProgressStats {
        /// Bytes moved over the wire
        internal let bytesDownloaded_ = ManagedAtomic<Int>(0)
        /// Bytes logically copied over
        internal let bytesExported_ = ManagedAtomic<Int>(0)
        /// Bytes that have to be copied
        internal let bytesToExport_ = ManagedAtomic<Int>(0)
        /// Files/directories that have been synced
        internal let objectsExported_ = ManagedAtomic<Int>(0)
        /// Files/directories that have to be copied
        internal let objectsToExport_ = ManagedAtomic<Int>(0)
        /// Concurrent downloads in progress
        internal let downloadsInProgressObjects_ = ManagedAtomic<Int>(0)

        public var bytesDownloaded: Int { bytesDownloaded_.load(ordering: .relaxed) }
        public var bytesExported: Int { bytesExported_.load(ordering: .relaxed) }
        public var bytesToExport: Int { bytesToExport_.load(ordering: .relaxed) }
        public var objectsExported: Int { objectsExported_.load(ordering: .relaxed) }
        public var objectsToExport: Int { objectsToExport_.load(ordering: .relaxed) }
        public var downloadsInProgressObjects: Int { downloadsInProgressObjects_.load(ordering: .relaxed) }

        public var debugDescription: String {
            return """
                {bytesDownloaded: \(bytesDownloaded), \
                bytesExported: \(bytesExported), \
                bytesToExport: \(bytesToExport), \
                objectsExported: \(objectsExported), \
                objectsToExport: \(objectsToExport), \
                downloadsInProgressObjects: \(downloadsInProgressObjects)}
                """
        }

        public init() { }
    }

    /// Export an entire filesystem subtree [to disk].
    ///
    /// - Parameters:
    ///   - id:             The ID of the tree to export.
    ///   - from:           The database to import the content into.
    ///   - to:             The path to write the content to.
    ///   - materializer:   How to save files [to disk].
    static func export(
        _ id: LLBDataID,
        from db: LLBCASDatabase,
        to exportPathPrefix: AbsolutePath,
        materializer: LLBFilesystemObjectMaterializer = LLBRealFilesystemMaterializer(),
        storageBatcher: LLBBatchingFutureOperationQueue? = nil,
        stats: ExportProgressStats? = nil,
        _ ctx: Context
    ) -> LLBFuture<Void> {
        let storageBatcher = storageBatcher ?? ctx.fileTreeExportStorageBatcher
        let stats = stats ?? .init()
        let delegate = CASFileTreeWalkerDelegate(from: db, to: exportPathPrefix, materializer: materializer, storageBatcher: storageBatcher, stats: stats)

        let walker = ConcurrentHierarchyWalker(group: db.group, delegate: delegate)
        stats.objectsToExport_.wrappingIncrement(ordering: .relaxed)
        return walker.walk(.init(id: id, exportPath: exportPathPrefix, kindHint: nil), ctx)
    }
}


private final class CASFileTreeWalkerDelegate: RetrieveChildrenProtocol {
    let db: LLBCASDatabase
    let exportPathPrefix: AbsolutePath
    let materializer: LLBFilesystemObjectMaterializer
    let stats: LLBCASFileTree.ExportProgressStats
    let storageBatcher: LLBBatchingFutureOperationQueue?

    struct Item {
        let id: LLBDataID
        let exportPath: AbsolutePath
        let kindHint: AnnotatedCASTreeChunk.ItemKind?
    }

    let allocator = LLBByteBufferAllocator()

    init(from db: LLBCASDatabase, to exportPathPrefix: AbsolutePath, materializer: LLBFilesystemObjectMaterializer, storageBatcher: LLBBatchingFutureOperationQueue?, stats: LLBCASFileTree.ExportProgressStats) {
        self.db = db
        self.exportPathPrefix = exportPathPrefix
        self.materializer = materializer
        self.stats = stats
        self.storageBatcher = storageBatcher
    }

    /// Conformance to `RetrieveChildrenProtocol`.
    func children(of item: Item, _ ctx: Context) -> LLBFuture<[Item]> {

        stats.downloadsInProgressObjects_.wrappingIncrement(ordering: .relaxed)

        let casObjectFuture: LLBFuture<LLBCASObject> = db.get(item.id, ctx).flatMapThrowing { casObject in
            self.stats.downloadsInProgressObjects_.wrappingDecrement(ordering: .relaxed)

            guard let casObject = casObject else {
                throw LLBExportError.missingReference(item.id)
            }

            self.stats.bytesDownloaded_.wrappingIncrement(by: casObject.data.readableBytes, ordering: .relaxed)

            return casObject
        }

        if let batcher = self.storageBatcher {
          return casObjectFuture.flatMap { casObject in
            // Unblock the current NIO thread.
            batcher.execute {
                try self.parseAndMaterialize(casObject, item).map {
                    Item(id: $0.id, exportPath: $0.path, kindHint: $0.kind)
                }
            }
          }
        } else {
          return casObjectFuture.flatMapThrowing { casObject in
            try self.parseAndMaterialize(casObject, item).map {
                Item(id: $0.id, exportPath: $0.path, kindHint: $0.kind)
            }
          }
        }
    }


    /// Parse (may include buffer management, uncompression, copying)
    /// and materialize (going to the file system). This may or may not
    /// be run on the NIO threads, so don't wait().
    private func parseAndMaterialize(_ casObject: LLBCASObject, _ item: Item) throws -> [AnnotatedCASTreeChunk] {
        let (fsObject, others) = try CASFileTreeParser(for: self.exportPathPrefix, allocator: allocator).parseCASObject(id: item.id, path: item.exportPath, casObject: casObject, kind: item.kindHint)

        // Save some statistics.
        if case .directory = fsObject.content {
            var aggregateSize: Int = 0

            for entry in others {
                let (newAggregate, overflow) = aggregateSize.addingReportingOverflow(Int(clamping: entry.kind.overestimatedSize))
                aggregateSize = newAggregate
                assert(!overflow)
            }

            stats.objectsToExport_.wrappingIncrement(by: others.count, ordering: .relaxed)

            // If we downloaded the top object to figure out how much
            // we need to download, add that top object's size to aggregate.
            if self.stats.bytesExported_.load(ordering: .relaxed) == 0 {
                aggregateSize += casObject.data.readableBytes
            }

            // Record the largest aggregate size (top level?)
            repeat {
                let old = stats.bytesToExport_.load(ordering: .relaxed)
                guard aggregateSize > old else { break }
                guard
                    !self.stats.bytesToExport_.compareExchange(
                        expected: old, desired: aggregateSize, ordering: .sequentiallyConsistent
                    ).0
                else {
                    break
                }
            } while aggregateSize > stats.bytesToExport_.load(ordering: .relaxed)
        }

        do {
            try materializer.materialize(object: fsObject)
        } catch {
            throw LLBExportError.ioError(error)
        }
        stats.bytesExported_.wrappingIncrement(by: fsObject.accountedDataSize, ordering: .relaxed)
        stats.objectsExported_.wrappingIncrement(by: fsObject.accountedObjects, ordering: .relaxed)
        return others
    }
}
