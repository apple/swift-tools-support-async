// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import TSCUtility
import TSFCAS

/// The stream protocols provide an abstraction for reading and writing content that is generated from a stream (such
/// as stdout/stderr) in a CAS efficient manner. The intention is that implementation of these procotols are designed
/// to minimize storage structure as new data is appended, in order to minimize roundtrips to the CAS and maximize the
/// immutability trait. The intention is not to force different implementations to be compatible, so stream stored under
/// a particular writer implementation should be read with its matching reader implementation.

/// Writer protocol for storing stream data.
public protocol LLBCASStreamWriter {
    var latestID: LLBFuture<LLBDataID>? { get }

    /// Appends data into the stream data structure under the specified channel. Returns a future with the LLBDataID
    /// to a valid stream data structure that can be read using a LLBCASStreamReader implementation.
    @discardableResult
    mutating func append(data: LLBByteBuffer, channel: UInt8, _ ctx: Context) -> LLBFuture<LLBDataID>
}

// Convenience extension for default parameters.
public extension LLBCASStreamWriter {
    @discardableResult
    @inlinable
    mutating func append(data: LLBByteBuffer, _ ctx: Context) -> LLBFuture<LLBDataID> {
        return append(data: data, channel: 0, ctx)
    }
}

/// Reader protocol for stored stream data.
public protocol LLBCASStreamReader {
    /// Reads from the stream pointed by the id parameter. If channels is not specified, it will read all the channels,
    /// in the order they were appended, otherwise will only provide data from the specified channels. If lastReadID
    /// is provided, the stream will start at the given ID, otherwise it will read from the beginning of the stream.
    /// Read happens through the provided closure, which provides the data chunk along with the channel it was stored
    /// under.
    func read(
        id: LLBDataID,
        channels: [UInt8]?,
        lastReadID: LLBDataID?,
        _ ctx: Context,
        readerBlock: @escaping (UInt8, LLBByteBuffer) throws -> Bool
    ) -> LLBFuture<Void>
}

// Convenience extension for default parameters.
public extension LLBCASStreamReader {
    @inlinable
    func read(
        id: LLBDataID,
        _ ctx: Context,
        readerBlock: @escaping (UInt8, LLBByteBuffer) throws -> Bool
    ) -> LLBFuture<Void> {
        return read(id: id, channels: nil, lastReadID: nil, ctx, readerBlock: readerBlock)
    }

    @inlinable
    func read(
        id: LLBDataID,
        channels: [UInt8],
        _ ctx: Context,
        readerBlock: @escaping (UInt8, LLBByteBuffer) throws -> Bool
    ) -> LLBFuture<Void> {
        return read(id: id, channels: channels, lastReadID: nil, ctx, readerBlock: readerBlock)
    }

    @inlinable
    func read(
        id: LLBDataID,
        lastReadID: LLBDataID,
        _ ctx: Context,
        readerBlock: @escaping (UInt8, LLBByteBuffer) throws -> Bool
    ) -> LLBFuture<Void> {
        return read(id: id, channels: nil, lastReadID: lastReadID, ctx, readerBlock: readerBlock)
    }
}

/// Common error types for stream protocol implementations.
public enum LLBCASStreamError: Error {
    case invalid
    case missing
}
