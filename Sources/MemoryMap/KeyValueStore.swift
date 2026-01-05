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
import os

/// A persistent key-value store backed by memory-mapped files.
///
/// `KeyValueStore` provides a Dictionary-like interface with crash-resilient storage.
/// All data is automatically persisted to disk via memory mapping.
///
/// ## Requirements
/// - **Capacity**: Fixed at 256 entries. Not resizable after creation.
///
/// ## Storage Details
/// Uses a hash table with double hashing for collision resolution. Deleted entries
/// leave tombstones that can degrade performance. Call `compact()` periodically to
/// remove tombstones and improve lookup speed.
///
/// ## Example
/// ```swift
/// struct MyValue {
///     var counter: Int
///     var timestamp: Double
/// }
///
/// let store = try KeyValueStore<MyValue>(fileURL: url)
///
/// // Dictionary-like subscript access
/// store["user:123"] = MyValue(counter: 1, timestamp: Date().timeIntervalSince1970)
/// if let value = store["user:123"] {
///     print("Counter: \(value.counter)")
/// }
///
/// // Access with default value
/// let count = store["user:456", default: MyValue(counter: 0, timestamp: 0)].counter
///
/// // Explicit error handling
/// try store.setValue(MyValue(counter: 2, timestamp: Date().timeIntervalSince1970), for: "user:123")
///
/// // Iterate over keys
/// for key in store.keys {
///     print("Key: \(key)")
/// }
/// ```
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
public class KeyValueStore<Key: BasicTypeCompliance, Value: BitwiseCopyable>: @unchecked Sendable {
  /// The URL of the memory-mapped file backing this store
  public var url: URL {
    memoryMap.url
  }

  /// Accesses the value for the given key, or returns a default value if the key isn't found.
  ///
  /// - Parameters:
  ///   - key: The key to look up
  ///   - defaultValue: The value to return if the key doesn't exist
  /// - Returns: The stored value, or the default value if the key isn't found
  public subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
    _value(for: key) ?? defaultValue()
  }

  /// Creates or opens a key-value store at the specified file location.
  ///
  /// The store is backed by a memory-mapped file that persists data to disk.
  /// Capacity is fixed at 256 entries and cannot be changed.
  ///
  /// - Parameters:
  ///   - fileURL: The file location for the memory-mapped store
  ///   - lock: The lock implementation to use (defaults to OSAllocatedUnfairLock)
  ///
  /// - Throws:
  ///   - File system errors if the file cannot be created or opened
  ///
  /// - Note: Value must be a POD (Plain Old Data) type with no references or object pointers.
  public init(fileURL: URL, lock: MemoryMapLock = DefaultMemoryMapLock()) throws {
    precondition(_isPOD(Value.self), "Value type must be POD (Plain Old Data)")
    memoryMap = try MemoryMap<KeyValueStoreStorage<Key, Value>>(fileURL: fileURL, lock: lock)
  }

  /// Returns all keys currently stored.
  ///
  /// The order of keys is not guaranteed and may change between calls.
  ///
  /// - Returns: An array of all keys in the store
  public var keys: [Key] {
    memoryMap.withLockedStorage { storage in
      var keys: [Key] = []
      self.forEachOccupiedEntry(in: &storage) { key, _ in
        keys.append(key)
      }
      return keys
    }
  }

  /// Accesses the value associated with the given key for reading and writing.
  ///
  /// This version accepts a validated Key, ensuring compile-time or explicit validation.
  ///
  /// - Note: Assignment failures (e.g., when the store is full) fail silently.
  ///   Use `setValue(_:for:)` if you need explicit error handling.
  public subscript(key: Key) -> Value? {
    get { _value(for: key) }
    set {
      do {
        try _setValue(newValue, for: key)
      } catch {
        // Silently ignore errors (e.g., store full) for subscript convenience
        // Use setValue(_:for:) if you need error handling
      }
    }
  }

  /// Sets or removes a value for the given key.
  ///
  /// Use this method when you need explicit error handling. For convenience,
  /// use subscript assignment instead.
  ///
  /// - Parameters:
  ///   - value: The value to store, or `nil` to remove the key
  ///   - key: The key to associate with the value
  ///
  /// - Throws: `KeyValueStoreError.storeFull` if the store is at capacity and the key doesn't exist
  public func setValue(_ value: Value?, for key: Key) throws {
    try _setValue(value, for: key)
  }

  /// Returns the value for the given key.
  ///
  /// - Parameter key: The key to look up
  /// - Returns: The stored value, or `nil` if the key doesn't exist
  public func value(for key: Key) -> Value? {
    _value(for: key)
  }

  /// Returns whether the store contains the given key.
  ///
  /// - Parameter key: The key to check
  /// - Returns: `true` if the key exists, `false` otherwise
  public func contains(_ key: Key) -> Bool {
    memoryMap.withLockedStorage { storage in
      if case .found = self.probeSlot(for: key, in: &storage) {
        return true
      }
      return false
    }
  }

  /// Removes all entries from the store.
  public func removeAll() {
    memoryMap.withLockedStorage { storage in
      storage.entries.reset()
    }
  }

  /// Compacts the store by removing tombstones and reorganizing entries.
  ///
  /// This method improves lookup performance by eliminating tombstones that
  /// can cause long probe chains. It collects all active entries, clears the
  /// table, and reinserts them with fresh hash positions.
  ///
  /// - Warning: This operation writes to all 256 hash table slots, resulting
  ///   in significant disk I/O since the store is backed by a memory-mapped file.
  ///   Call this method deliberately when you can afford the I/O cost (e.g.,
  ///   during maintenance windows or when the store is idle).
  ///
  /// - Note: Compaction is NOT automatic. You control when this expensive
  ///   operation occurs. Monitor tombstone accumulation and compact when needed.
  public func compact() {
    memoryMap.withLockedStorage { storage in
      compactInternal(storage: &storage)
    }
  }

  /// Returns a standard Swift Dictionary containing all key-value pairs from the store.
  ///
  /// This creates a copy of the data, allowing you to use all Dictionary methods
  /// and collection operations.
  ///
  /// - Returns: A Dictionary with all keys and values from the store
  public func dictionaryRepresentation() -> [Key: Value] {
    memoryMap.withLockedStorage { storage in
      var dict: [Key: Value] = [:]
      self.forEachOccupiedEntry(in: &storage) { key, value in
        dict[key] = value
      }
      return dict
    }
  }

  /// Private storage
  let memoryMap: MemoryMap<KeyValueStoreStorage<Key, Value>>
}

// MARK: - Errors

/// Errors that can occur during KeyValueStore operations
public enum KeyValueStoreError: Error {
  /// The store has reached its maximum capacity and cannot accept new entries
  case storeFull
  /// The items type's size exceeds the maximum allowed size
  case tooLarge
}
