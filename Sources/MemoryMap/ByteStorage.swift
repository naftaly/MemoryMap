/// MIT License
///
/// Copyright (c) 2025 Alexander Cohen
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in all
/// copies or substantial portions of the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
/// SOFTWARE.

import Foundation

/// Protocol for fixed-size byte storage using tuples for POD compliance.
///
/// Provides a way to create fixed-size storage buffers that remain POD (Plain Old Data) types,
/// which is required for safe memory-mapped file storage. Uses tuples instead of arrays to
/// maintain trivial type guarantees.
///
/// You typically won't implement this yourself - use `ByteStorage60` or `ByteStorage1020` instead.
public protocol ByteStorage {
    /// The underlying storage type (a tuple of Int8 values)
    associatedtype Storage: Sendable

    /// The storage capacity in bytes
    static var capacity: Int { get }

    /// Creates a new zero-initialized storage instance
    static func make() -> Storage
}

public extension ByteStorage {
    /// Capacity of the storage in bytes
    @inline(__always)
    static var capacity: Int {
        MemoryLayout<Storage>.size
    }

    @inline(__always)
    static func make() -> Storage {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity) { buffer in
            buffer.initialize(repeating: 0)
            return UnsafeRawPointer(buffer.baseAddress!).loadUnaligned(as: Storage.self)
        }
    }

    // MARK: - Generic Storage Methods

    /// Stores a fixed-size value in storage
    @inline(__always)
    static func store<T>(_ value: T) -> Storage {
        precondition(
            MemoryLayout<T>.size <= capacity,
            "Value too large for \(Storage.self) (capacity: \(capacity))"
        )
        var storage = make()
        withUnsafeMutableBytes(of: &storage) { ptr in
            ptr.storeBytes(of: value, as: T.self)
        }
        return storage
    }

    /// Extracts a fixed-size value from storage
    @inline(__always)
    static func extract<T>(_: T.Type = T.self, from storage: Storage) -> T {
        precondition(
            MemoryLayout<T>.size <= capacity,
            "Type \(T.self):\(MemoryLayout<T>.size) too large for \(Storage.self):\(capacity)"
        )
        return withUnsafePointer(to: storage) { ptr in
            UnsafeRawPointer(ptr).loadUnaligned(as: T.self)
        }
    }

    // MARK: - String Storage Methods

    /// Stores a String in storage with length prefix
    @inline(__always)
    static func store(_ string: String) -> (storage: Storage, length: UInt16, fits: Bool) {
        var storage = make()

        var fits = true
        var written = 0
        withUnsafeMutableBytes(of: &storage) { ptr in
            let buffer = ptr.bindMemory(to: UInt8.self)

            // Start writing after the length prefix
            for scalar in string.unicodeScalars {
                let utf8 = UTF8.encode(scalar)!
                let count = utf8.count

                // Only write if entire code point fits
                guard written + count <= capacity else {
                    fits = false
                    break
                }

                for byte in utf8 {
                    buffer[written] = byte
                    written += 1
                }
            }
        }

        return (storage, UInt16(written), fits)
    }

    /// Extracts a String from storage
    @inline(__always)
    static func extractString(from storage: Storage, length: UInt16) -> String {
        withUnsafeBytes(of: storage) { ptr in
            let length = min(Int(length), capacity)
            let bytes = UnsafeBufferPointer(
                start: ptr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                count: length
            )
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}

// MARK: - Storage Size Constants

/// 8-byte fixed storage using a tuple-based buffer.
///
/// Provides minimal storage suitable for numeric types only (Int, UInt, Double, Float, etc.).
/// The largest numeric types (Int64, UInt64, Double) require exactly 8 bytes.
/// With 3 bytes of metadata in BasicType, total size is ~11 bytes (stride may be larger due to alignment).
public struct ByteStorage8: ByteStorage {
    public typealias Storage = (
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8
    )
}

/// 60-byte fixed storage using a tuple-based buffer.
///
/// Provides compact storage suitable for short strings (~60 characters) or small data.
/// Used by `BasicType64` which adds 3 bytes of metadata (size: ~63 bytes, stride may be larger).
public struct ByteStorage60: ByteStorage {
    public typealias Storage = (
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8
    )
}

/// 1020-byte fixed storage using a tuple-based buffer.
///
/// Provides large storage suitable for longer strings (~1000 characters) or larger data.
/// Used by `BasicType1024` which adds 3 bytes of metadata (size: ~1023 bytes, stride may be larger).
public struct ByteStorage1020: ByteStorage {
    public typealias Storage = (
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8
    )
}
