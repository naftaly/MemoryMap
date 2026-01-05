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

/// Protocol conformance required for types that can be used as keys in KeyValueStore.
///
/// Combines Hashable, Sendable, and custom equality/hashing protocols for efficient
/// memory-mapped storage with double hashing.
public typealias BasicTypeCompliance = Hashable & Sendable & _BasicTypeEquatable
  & _BasicTypeHashable & BitwiseCopyable

/// A type-safe wrapper for storing basic Swift types with 1020 bytes of storage.
///
/// Use this for keys or values that need to store longer strings (up to ~1000 characters).
/// Size: ~1023 bytes (1020 bytes storage + 3 bytes metadata). Stride may be slightly larger due to alignment.
public typealias BasicType1024 = _BasicType<ByteStorage1020>

/// A type-safe wrapper for storing basic Swift types with 60 bytes of storage.
///
/// Use this for keys or values with shorter strings (up to ~60 characters).
/// Size: ~63 bytes (60 bytes storage + 3 bytes metadata). Stride may be slightly larger due to alignment.
public typealias BasicType64 = _BasicType<ByteStorage60>

/// A type-safe wrapper for storing basic Swift types with 8 bytes of storage.
///
/// Use this for compact keys or values with numeric types.
/// Size: ~11 bytes (8 bytes storage + 3 bytes metadata). Stride may be slightly larger due to alignment.
/// Suitable for Int, UInt, Double, Float, Bool and their sized variants.
public typealias BasicType8 = _BasicType<ByteStorage8>
public typealias BasicTypeNumber = BasicType8

/// A type-safe container for basic Swift types optimized for memory-mapped storage.
///
/// Stores Int, UInt, Double, Float, Bool, and String values in a fixed-size buffer.
/// Designed to be a POD (Plain Old Data) type for safe persistence in memory-mapped files.
///
/// ## Supported Types
/// - Integers: Int, Int8, Int16, Int32, Int64, UInt, UInt8, UInt16, UInt32, UInt64
/// - Floating point: Double, Float
/// - Boolean: Bool
/// - String: UTF-8 encoded, length limited by storage size
///
/// ## Example
/// ```swift
/// let key = BasicType64("user:123")
/// let value = BasicType64(42)
/// store[key] = myData
/// ```
@frozen
public struct _BasicType<Storage: ByteStorage>: BasicTypeCompliance {
  public typealias StorageInfo = Storage

  /// The type of value stored in this BasicType instance.
  public enum Kind: UInt8, Sendable, BitwiseCopyable {
    case int
    case int8
    case int16
    case int32
    case int64
    case uint
    case uint8
    case uint16
    case uint32
    case uint64
    case double
    case float
    case bool
    case string
  }

  /// The type of value stored
  public let kind: Kind

  /// The number of bytes used in storage
  public let length: UInt16

  /// Raw storage buffer
  let value: StorageInfo.Storage

  public init(kind: Kind, length: UInt16, value: StorageInfo.Storage) {
    self.kind = kind
    self.length = length
    self.value = value
  }
}

// MARK: - Initializers

extension _BasicType {
  @inline(__always)
  public init(_ integer: Int) {
    self.init(
      kind: .int,
      length: UInt16(MemoryLayout<Int>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ integer: Int8) {
    self.init(
      kind: .int8,
      length: UInt16(MemoryLayout<Int8>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ integer: Int16) {
    self.init(
      kind: .int16,
      length: UInt16(MemoryLayout<Int16>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ integer: Int32) {
    self.init(
      kind: .int32,
      length: UInt16(MemoryLayout<Int32>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ integer: Int64) {
    self.init(
      kind: .int64,
      length: UInt16(MemoryLayout<Int64>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ integer: UInt) {
    self.init(
      kind: .uint,
      length: UInt16(MemoryLayout<UInt>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ integer: UInt8) {
    self.init(
      kind: .uint8,
      length: UInt16(MemoryLayout<UInt8>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ integer: UInt16) {
    self.init(
      kind: .uint16,
      length: UInt16(MemoryLayout<UInt16>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ integer: UInt32) {
    self.init(
      kind: .uint32,
      length: UInt16(MemoryLayout<UInt32>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ integer: UInt64) {
    self.init(
      kind: .uint64,
      length: UInt16(MemoryLayout<UInt64>.stride),
      value: StorageInfo.store(integer)
    )
  }

  @inline(__always)
  public init(_ double: Double) {
    self.init(
      kind: .double,
      length: UInt16(MemoryLayout<Double>.stride),
      value: StorageInfo.store(double)
    )
  }

  @inline(__always)
  public init(_ float: Float) {
    self.init(
      kind: .float,
      length: UInt16(MemoryLayout<Float>.stride),
      value: StorageInfo.store(float)
    )
  }

  @inline(__always)
  public init(_ bool: Bool) {
    self.init(
      kind: .bool,
      length: UInt16(MemoryLayout<Bool>.stride),
      value: StorageInfo.store(bool)
    )
  }

  @inline(__always)
  public init(throwing string: String) throws {
    let info = StorageInfo.store(string)
    guard info.fits else {
      throw KeyValueStoreError.tooLarge
    }
    self.init(
      kind: .string,
      length: UInt16(info.length),
      value: info.storage
    )
  }

  @inline(__always)
  public init(_ string: String) {
    let info = StorageInfo.store(string)
    self.init(
      kind: .string,
      length: UInt16(info.length),
      value: info.storage
    )
  }
}

// MARK: - ExpressibleBy ...

extension _BasicType: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self.init(value)
  }
}

extension _BasicType: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self.init(value)
  }
}

extension _BasicType: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) {
    self.init(value)
  }
}

extension _BasicType: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self.init(value)
  }
}

// MARK: - Value Extraction

extension _BasicType {
  /// Extracts the value as an Int.
  ///
  /// - Returns: The stored Int value, or `0` if this instance doesn't contain an Int
  @inline(__always)
  public var intValue: Int {
    guard kind == .int else { return 0 }
    return StorageInfo.extract(Int.self, from: value)
  }

  @inline(__always)
  public var int8Value: Int8 {
    guard kind == .int8 else { return 0 }
    return StorageInfo.extract(Int8.self, from: value)
  }

  @inline(__always)
  public var int16Value: Int16 {
    guard kind == .int16 else { return 0 }
    return StorageInfo.extract(Int16.self, from: value)
  }

  @inline(__always)
  public var int32Value: Int32 {
    guard kind == .int32 else { return 0 }
    return StorageInfo.extract(Int32.self, from: value)
  }

  @inline(__always)
  public var int64Value: Int64 {
    guard kind == .int64 else { return 0 }
    return StorageInfo.extract(Int64.self, from: value)
  }

  @inline(__always)
  public var uintValue: UInt {
    guard kind == .uint else { return 0 }
    return StorageInfo.extract(UInt.self, from: value)
  }

  @inline(__always)
  public var uint8Value: UInt8 {
    guard kind == .uint8 else { return 0 }
    return StorageInfo.extract(UInt8.self, from: value)
  }

  @inline(__always)
  public var uint16Value: UInt16 {
    guard kind == .uint16 else { return 0 }
    return StorageInfo.extract(UInt16.self, from: value)
  }

  @inline(__always)
  public var uint32Value: UInt32 {
    guard kind == .uint32 else { return 0 }
    return StorageInfo.extract(UInt32.self, from: value)
  }

  @inline(__always)
  public var uint64Value: UInt64 {
    guard kind == .uint64 else { return 0 }
    return StorageInfo.extract(UInt64.self, from: value)
  }

  @inline(__always)
  public var doubleValue: Double {
    guard kind == .double else { return 0.0 }
    return StorageInfo.extract(Double.self, from: value)
  }

  @inline(__always)
  public var floatValue: Float {
    guard kind == .float else { return 0.0 }
    return StorageInfo.extract(Float.self, from: value)
  }

  @inline(__always)
  public var boolValue: Bool {
    guard kind == .bool else { return false }
    return StorageInfo.extract(Bool.self, from: value)
  }

  /// Extracts the value as a String.
  ///
  /// - Returns: The stored String value, or an empty string if this instance doesn't contain a String
  @inline(__always)
  public var stringValue: String {
    guard kind == .string else { return "" }
    return StorageInfo.extractString(from: value, length: length)
  }
}

/// Protocol for BasicType equality comparison optimized for memory-mapped storage.
public protocol _BasicTypeEquatable: Equatable {}

/// Protocol for BasicType hash computation supporting double hashing.
public protocol _BasicTypeHashable {
  /// Computes two hash values for double hashing collision resolution.
  ///
  /// - Returns: A tuple of (hash1, hash2) where hash2 is derived from hash1 and guaranteed to be odd
  func hashes() -> (Int, Int)
}

// MARK: - Compliance

extension _BasicType {
  public static func == (lhs: _BasicType, rhs: _BasicType) -> Bool {
    guard lhs.length == rhs.length, lhs.kind == rhs.kind else {
      return false
    }
    // Optimize: use withUnsafeBytes once instead of per-byte subscript calls
    return withUnsafeBytes(of: lhs.value) { lhsPtr in
      withUnsafeBytes(of: rhs.value) { rhsPtr in
        let length = Int(lhs.length)
        return memcmp(lhsPtr.baseAddress, rhsPtr.baseAddress, length) == 0
      }
    }
  }
}

extension _BasicType {
  public func hash(into hasher: inout Hasher) {
    withUnsafeBytes(of: value) { ptr in
      hasher.combine(bytes: ptr)
    }
  }

  public func hashes() -> (Int, Int) {
    let hash1 = _hash1()
    let hash2 = _hash2(from: hash1)
    return (hash1, hash2)
  }

  private func _hash1() -> Int {
    // FNV-1a hash algorithm (better distribution than djb2)
    // Optimize: use withUnsafeBytes once instead of per-byte subscript calls
    withUnsafeBytes(of: value) { ptr in
      let buffer = ptr.bindMemory(to: UInt8.self)
      var hash: UInt64 = 14_695_981_039_346_656_037  // FNV offset basis
      let length = Int(length)
      for i in 0..<length {
        hash ^= UInt64(buffer[i])
        hash = hash &* 1_099_511_628_211  // FNV prime
      }
      // Ensure non-negative result
      return Int(hash & UInt64(Int.max))
    }
  }

  /// Derive second hash from first hash (much faster than computing separately)
  /// Use bit mixing to create independent distribution
  /// Must be odd (coprime with capacity=256) and never zero
  private func _hash2(from h1: Int) -> Int {
    // Mix bits: rotate and XOR to decorrelate from hash1
    let mixed = ((h1 >> 17) ^ (h1 << 15)) &+ (h1 >> 7)
    // Ensure odd by setting lowest bit
    return mixed | 1
  }
}
