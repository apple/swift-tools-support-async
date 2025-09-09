// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Foundation
import NIOCore

/// Something that exposes working withContiguousStorage
public enum LLBFastData {
    case slice(ArraySlice<UInt8>)
    case view(LLBByteBuffer)
    case data(Data)
    case pointer(UnsafeRawBufferPointer, deallocator: (UnsafeRawBufferPointer) -> Void)

    public init(_ data: [UInt8]) { self = .slice(ArraySlice(data)) }
    public init(_ data: ArraySlice<UInt8>) { self = .slice(data) }
    public init(_ data: LLBByteBuffer) { self = .view(data) }
    public init(_ data: Data) {
        precondition(data.regions.count == 1)
        self = .data(data)
    }
    public init(
        _ pointer: UnsafeRawBufferPointer, deallocator: @escaping (UnsafeRawBufferPointer) -> Void
    ) {
        self = .pointer(pointer, deallocator: deallocator)
    }

    public var count: Int {
        switch self {
        case .slice(let data):
            return data.count
        case .view(let data):
            return data.readableBytes
        case .data(let data):
            return data.count
        case .pointer(let ptr, _):
            return ptr.count
        }
    }

    public func withContiguousStorage<R>(_ cb: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows
        -> R
    {
        switch self {
        case .slice(let data):
            return try data.withContiguousStorageIfAvailable(cb)!
        case .view(let data):
            return try data.readableBytesView.withContiguousStorageIfAvailable(cb)!
        case .data(let data):
            precondition(data.regions.count == 1)
            return try data.withUnsafeBytes { rawPtr in
                let ptr = UnsafeRawBufferPointer(rawPtr).bindMemory(to: UInt8.self)
                return try cb(ptr)
            }
        case .pointer(let rawPtr, _):
            let ptr = UnsafeRawBufferPointer(rawPtr).bindMemory(to: UInt8.self)
            return try cb(ptr)
        }
    }
}
