import Foundation
import NIOConcurrencyHelpers
import TSCUtility
import TSFCAS

fileprivate extension LLBByteBuffer {
    var availableCapacity: Int { capacity - readableBytes }
}

/// Stream writer that buffers data before ingesting it into the CAS database.
public class LLBBufferedStreamWriter {
    private let bufferSize: Int
    private let lock = NIOConcurrencyHelpers.Lock()
    private var outputWriter: LLBLinkedListStreamWriter
    private var currentBuffer: LLBByteBuffer
    private var currentBufferedChannel: UInt8? = nil

    public var latestID: LLBFuture<LLBDataID>? {
        return lock.withLock { outputWriter.latestID }
    }

    /// Creates a new buffered writer, with a default buffer size of 512kb to optimize for roundtrip read time.
    public init(_ db: LLBCASDatabase, bufferSize: Int = 1 << 19) {
        self.outputWriter = LLBLinkedListStreamWriter(db)
        self.bufferSize = bufferSize
        self.currentBuffer = LLBByteBufferAllocator.init().buffer(capacity: bufferSize)
    }

    public func rebase(onto newBase: LLBDataID, _ ctx: Context) {
        lock.withLock {
            outputWriter.rebase(onto: newBase, ctx)
        }
    }

    /// Writes a chunk of data into the stream. Flushes if the current buffer would overflow, or if the data to write
    /// is larger than the buffer size.
    public func write(data: LLBByteBuffer, channel: UInt8, _ ctx: Context = .init()) {
        lock.withLock {
            if channel != currentBufferedChannel || data.readableBytes > currentBuffer.availableCapacity
            {
                _flush(ctx)
            }

            currentBufferedChannel = channel

            // If data is larger or equal than buffer size, send as is.
            if data.readableBytes >= bufferSize {
                outputWriter.append(data: data, channel: channel, ctx)
            } else {
                // data is smaller than max chunk, and if we were going to overpass the chunk size, the above check
                // would have already flushed the data, so at this point we know there's space in the buffer.
                assert(data.readableBytes <= currentBuffer.availableCapacity)
                currentBuffer.writeImmutableBuffer(data)
            }

            // If we filled the buffer, send it out.
            if currentBuffer.availableCapacity == 0 {
                _flush(ctx)
            }
        }
    }

    /// Flushes the buffer into the stream writer.
    public func flush(_ ctx: Context = .init()) {
        lock.withLock {
            _flush(ctx)
        }
    }

    /// Private implementation of flush, must be called within the lock.
    private func _flush(_ ctx: Context) {
        if currentBuffer.readableBytes > 0, let currentBufferedChannel = currentBufferedChannel {
            outputWriter.append(
                data: currentBuffer,
                channel: currentBufferedChannel, ctx
            )
            currentBuffer.clear()
        }
    }
}
