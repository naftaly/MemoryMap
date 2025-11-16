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

/// Maximum length for string keys (in bytes)
public let KeyValueStoreMaxKeyLength = 64

/// Default capacity for the key-value store
public let KeyValueStoreDefaultCapacity = 128

/// Default maximum size for POD values (in bytes)
public let KeyValueStoreDefaultMaxValueSize = 1024

/// A persistent key-value store backed by memory-mapped files.
///
/// `KeyValueStore` provides a Dictionary-like interface with crash-resilient storage.
/// All data is automatically persisted to disk via memory mapping.
///
/// ## Requirements
/// - **Keys**: Strings up to 64 bytes (UTF-8). Longer keys are truncated.
/// - **Values**: Must be POD (Plain Old Data) types with no references or classes.
///   Maximum value size is 1024 bytes.
/// - **Capacity**: Fixed at 128 entries. Not resizable after creation.
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
public class KeyValueStore<Value>: @unchecked Sendable {
    /// A validated string key for KeyValueStore.
    ///
    /// Keys are limited to 64 bytes of UTF-8 data. Longer strings are handled differently
    /// in debug vs release builds for safety.
    public struct Key: Sendable {
        /// Low-level storage representation
        let keyArray: KeyStorage

        /// Creates a key from a string.
        ///
        /// Keys are limited to 64 bytes (UTF-8). If the string exceeds this limit,
        /// it will be silently truncated to fit (respecting UTF-8 character boundaries).
        ///
        /// - Parameter string: The string to use as a key (max 64 bytes UTF-8)
        public init(_ string: String) {
            keyArray = KeyStorage(truncating: string)
        }
    }

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
    /// Capacity is fixed at 128 entries and cannot be changed.
    ///
    /// - Parameter fileURL: The file location for the memory-mapped store
    ///
    /// - Throws:
    ///   - `KeyValueStoreError.valueTooLarge` if the Value type exceeds 1024 bytes
    ///   - File system errors if the file cannot be created or opened
    ///
    /// - Note: Value must be a POD (Plain Old Data) type with no references or object pointers.
    public init(fileURL: URL) throws {
        guard MemoryLayout<Value>.stride <= KeyValueStoreDefaultMaxValueSize else {
            throw KeyValueStoreError.valueTooLarge
        }
        memoryMap = try MemoryMap<KeyValueStoreStorage<Value>>(fileURL: fileURL)
    }

    /// Returns all keys currently stored.
    ///
    /// The order of keys is not guaranteed and may change between calls.
    ///
    /// - Returns: An array of all keys in the store
    public var keys: [String] {
        memoryMap.withLockedStorage { storage in
            var keys: [String] = []
            self.forEachOccupiedEntry(in: &storage) { key, _ in
                keys.append(key.string)
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
            if case .found = self.probeSlot(for: key.keyArray, in: &storage) {
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
    /// - Warning: This operation writes to all 128 hash table slots, resulting
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
    public func dictionaryRepresentation() -> [String: Value] {
        memoryMap.withLockedStorage { storage in
            var dict: [String: Value] = [:]
            self.forEachOccupiedEntry(in: &storage) { key, value in
                dict[key.string] = value
            }
            return dict
        }
    }

    /// Private storage
    private let memoryMap: MemoryMap<KeyValueStoreStorage<Value>>
}

// MARK: - String Convenience API

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
public extension KeyValueStore {
    /// Accesses the value associated with the given key for reading and writing.
    ///
    /// This is a convenience method that accepts a String.
    ///
    /// - Note: Keys longer than 64 bytes will be truncated in release builds (assertion in debug).
    ///   Assignment failures (e.g., when the store is full) fail silently.
    ///   Use `setValue(_:for:)` if you need explicit error handling.
    subscript(key: String) -> Value? {
        get {
            self[Key(key)]
        }
        set {
            self[Key(key)] = newValue
        }
    }

    /// Accesses the value for the given key, or returns a default value if the key isn't found.
    ///
    /// Convenience method that accepts a String instead of a Key.
    ///
    /// - Parameters:
    ///   - key: The key to look up (max 64 bytes UTF-8)
    ///   - defaultValue: The value to return if the key doesn't exist
    /// - Returns: The stored value, or the default value if the key isn't found
    ///
    /// - Note: Keys longer than 64 bytes will be truncated in release builds (assertion in debug).
    subscript(key: String, default defaultValue: @autoclosure () -> Value) -> Value {
        self[Key(key), default: defaultValue()]
    }

    /// Returns whether the store contains the given key.
    ///
    /// Convenience method that accepts a String instead of a Key.
    ///
    /// - Parameter key: The key to check (max 64 bytes UTF-8)
    /// - Returns: `true` if the key exists, `false` otherwise
    ///
    /// - Note: Keys longer than 64 bytes will be truncated in release builds (assertion in debug).
    func contains(_ key: String) -> Bool {
        contains(Key(key))
    }
}

// MARK: - ExpressibleByStringLiteral

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
extension KeyValueStore.Key: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        // String literals are compile-time constants
        // Assert will catch invalid literals during development
        self.init(value)
    }
}

// MARK: - Private KeyValueStore

extension KeyValueStore {
    private func forEachOccupiedEntry(
        in storage: inout KeyValueStoreStorage<Value>,
        _ body: (KeyStorage, Value) -> Void
    ) {
        for i in 0 ..< KeyValueStoreDefaultCapacity {
            let entry = storage.entries[i]
            if entry.state == .occupied {
                body(entry.key, entry.value)
            }
        }
    }

    private func probeSlot(for key: KeyStorage, in storage: inout KeyValueStoreStorage<Value>) -> ProbeResult {
        precondition(
            KeyValueStoreDefaultCapacity & (KeyValueStoreDefaultCapacity - 1) == 0,
            "Capacity must be a power of two"
        )
        let hash1 = key.hashKey
        let step = key.hash2(from: hash1)
        let startIndex = hash1 & (KeyValueStoreDefaultCapacity - 1)
        var index = startIndex
        var probeCount = 0
        var firstTombstoneIndex: Int?

        while probeCount < KeyValueStoreDefaultCapacity {
            let entry = storage.entries[index]

            switch entry.state {
            case .occupied:
                if entry.key == key {
                    return .found(index)
                }
            // Robin Hood: check if our probe distance exceeds the resident's
            // If so, this is a good insertion point (we'd swap in actual insertion)
            case .tombstone:
                if firstTombstoneIndex == nil {
                    firstTombstoneIndex = index
                }
            case .empty:
                return .available(firstTombstoneIndex ?? index)
            }

            // Double hashing: increment by step (eliminates multiplication)
            probeCount += 1
            index = (index &+ step) & (KeyValueStoreDefaultCapacity - 1)
        }

        if let tombstoneIndex = firstTombstoneIndex {
            return .available(tombstoneIndex)
        }

        return .full
    }

    private func _setValue(_ value: Value?, for key: Key) throws {
        let keyArray = key.keyArray

        return try memoryMap.withLockedStorage { storage in
            switch self.probeSlot(for: keyArray, in: &storage) {
            case let .found(index):
                var updatedEntry = storage.entries[index]
                if let value {
                    updatedEntry.value = value
                } else {
                    updatedEntry.state = .tombstone
                }
                storage.entries[index] = updatedEntry
            case let .available(index):
                if let value {
                    storage.entries[index] = KeyValueEntry(
                        key: keyArray,
                        value: value,
                        state: .occupied
                    )
                }
            case .full:
                if value != nil {
                    throw KeyValueStoreError.storeFull
                }
            }
        }
    }

    private func _value(for key: Key) -> Value? {
        memoryMap.withLockedStorage { storage in
            guard case let .found(index) = self.probeSlot(for: key.keyArray, in: &storage) else {
                return nil
            }
            let entry = storage.entries[index]
            return entry.value
        }
    }

    private func compactInternal(storage: inout KeyValueStoreStorage<Value>) {
        // Collect all active entries
        var activeEntries: [(key: KeyStorage, value: Value)] = []

        for i in 0 ..< KeyValueStoreDefaultCapacity {
            let entry = storage.entries[i]
            if entry.state == .occupied {
                activeEntries.append((key: entry.key, value: entry.value))
            }
        }

        // Clear the entire table
        storage.entries.reset()

        // Reinsert all entries with fresh hash positions using double hashing
        for (key, value) in activeEntries {
            let hash1 = key.hashKey
            let step = key.hash2(from: hash1)
            var index = hash1 & (KeyValueStoreDefaultCapacity - 1)
            var probeCount = 0

            // Find the first empty slot (no tombstones after clearing)
            var inserted = false
            while probeCount < KeyValueStoreDefaultCapacity {
                let entry = storage.entries[index]
                if entry.state == .empty {
                    storage.entries[index] = KeyValueEntry(
                        key: key,
                        value: value,
                        state: .occupied
                    )
                    inserted = true
                    break
                }
                // Double hashing: increment by step (eliminates multiplication)
                probeCount += 1
                index = (index &+ step) & (KeyValueStoreDefaultCapacity - 1)
            }

            // This should never fail since we just cleared the table and are reinserting
            // the same number of entries, but guard against data loss
            precondition(inserted, "Failed to reinsert entry during compaction")
        }
    }

    /// The number of key-value pairs in the store (calculated on-demand)
    var count: Int {
        memoryMap.withLockedStorage { storage in
            var count = 0
            for i in 0 ..< KeyValueStoreDefaultCapacity {
                if storage.entries[i].state == .occupied {
                    count += 1
                }
            }
            return count
        }
    }

    /// A Boolean value indicating whether the store is empty (calculated on-demand)
    var isEmpty: Bool {
        memoryMap.withLockedStorage { storage in
            for i in 0 ..< KeyValueStoreDefaultCapacity {
                if storage.entries[i].state == .occupied {
                    return false
                }
            }
            return true
        }
    }
}

private enum ProbeResult {
    case found(Int)
    case available(Int)
    case full
}

// MARK: - POD Types

/// Storage container for the key-value store.
///
/// This structure holds the hash table entries.
/// It is designed to be a POD (Plain Old Data) type for efficient memory-mapped storage.
struct KeyValueStoreStorage<Value> {
    /// Fixed-size array of hash table entries
    var entries: KeyValueStoreEntries<Value>
}

/// Fixed-size key storage (64 bytes) plus tracked length
struct KeyStorage: @unchecked Sendable, Equatable {
    // Public storage ensures the struct remains trivial/POD
    typealias Storage64 = (
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8
    )
    let storage: Storage64
    let length: UInt8

    /// Default initializer - creates a zero-filled key
    init() {
        storage = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
        length = 0
    }

    /// Creates a KeyStorage from a String, truncating if necessary
    init(truncating string: String) {
        let result = Self.packString(string)
        // Silently truncate - no assertion for truncating init
        storage = result.storage
        length = result.usedBytes
    }

    init(_ string: String) throws {
        let result = Self.packString(string)
        guard result.fits else {
            throw KeyValueStoreError.keyTooLong
        }
        storage = result.storage
        length = result.usedBytes
    }

    /// Packs a string into a 64-byte storage tuple, preserving UTF-8 character boundaries
    static func packString(_ string: String) -> (storage: Storage64, usedBytes: UInt8, fits: Bool) {
        var storage = KeyStorage().storage
        var fits = true

        let written = withUnsafeMutableBytes(of: &storage) { buffer in
            let dest = buffer.bindMemory(to: UInt8.self)
            var written = 0

            for scalar in string.unicodeScalars {
                let utf8 = UTF8.encode(scalar)!
                let count = utf8.count

                // Only write if entire code point fits
                guard written + count <= 64 else {
                    fits = false
                    break
                }

                for byte in utf8 {
                    dest[written] = byte
                    written += 1
                }
            }

            return written
        }

        return (storage, UInt8(written), fits)
    }

    /// Provides read-only byte access to the underlying storage
    ///
    /// - Parameter index: The byte index (must be 0..<64)
    /// - Returns: The byte at the specified index
    subscript(index: Int) -> Int8 {
        precondition(index >= 0 && index < 64, "Index out of bounds")
        return withUnsafeBytes(of: storage) { ptr in
            Int8(bitPattern: ptr[index])
        }
    }

    static func == (lhs: KeyStorage, rhs: KeyStorage) -> Bool {
        guard lhs.length == rhs.length else {
            return false
        }
        // Optimize: use withUnsafeBytes once instead of per-byte subscript calls
        return withUnsafeBytes(of: lhs.storage) { lhsPtr in
            withUnsafeBytes(of: rhs.storage) { rhsPtr in
                let length = Int(lhs.length)
                return memcmp(lhsPtr.baseAddress, rhsPtr.baseAddress, length) == 0
            }
        }
    }

    var hashKey: Int {
        // FNV-1a hash algorithm (better distribution than djb2)
        // Optimize: use withUnsafeBytes once instead of per-byte subscript calls
        withUnsafeBytes(of: storage) { ptr in
            let buffer = ptr.bindMemory(to: UInt8.self)
            var hash: UInt64 = 14_695_981_039_346_656_037 // FNV offset basis
            let length = Int(length)
            for i in 0 ..< length {
                hash ^= UInt64(buffer[i])
                hash = hash &* 1_099_511_628_211 // FNV prime
            }
            // Ensure non-negative result
            return Int(hash & UInt64(Int.max))
        }
    }

    /// Derive second hash from first hash (much faster than computing separately)
    /// Use bit mixing to create independent distribution
    /// Must be odd (coprime with capacity=128) and never zero
    func hash2(from h1: Int) -> Int {
        // Mix bits: rotate and XOR to decorrelate from hash1
        let mixed = ((h1 >> 17) ^ (h1 << 15)) &+ (h1 >> 7)
        // Ensure odd by setting lowest bit
        return mixed | 1
    }

    var string: String {
        withUnsafeBytes(of: storage) { ptr in
            let base = ptr.bindMemory(to: UInt8.self)
            let slice = UnsafeBufferPointer(start: base.baseAddress, count: Int(length))
            return String(decoding: slice, as: UTF8.self)
        }
    }
}

/// A single entry in the key-value store.
///
/// Each entry contains a key, value, and state indicator. This structure is designed
/// to be a POD type for efficient memory-mapped storage in a hash table using double hashing.
struct KeyValueEntry<Value> {
    /// The key for this entry
    var key: KeyStorage
    /// The value stored in this entry
    var value: Value

    /// State of a slot in the key-value store
    enum SlotState: UInt8 {
        /// Never used or fully cleared
        case empty = 0
        /// Contains a valid key-value pair
        case occupied = 1
        /// Previously occupied but deleted (maintains probe chains for double hashing)
        case tombstone = 2
    }

    /// The current state of this hash table slot
    var state: SlotState

    init(key: KeyStorage = KeyStorage(), value: Value, state: SlotState = .empty) {
        self.key = key
        self.value = value
        self.state = state
    }
}

/// Fixed-size array of 128 entries with subscript access.
///
/// This structure provides a fixed-capacity hash table storage using a tuple for the
/// underlying representation. The tuple ensures the struct remains a POD type, which is
/// required for safe memory-mapped storage.
struct KeyValueStoreEntries<Value> {
    /// Tuple-based storage for 128 entries (ensures POD/trivial type for memory mapping)
    var storage: (
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>,
        KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>, KeyValueEntry<Value>
    )

    /// Provides array-like subscript access to entries
    ///
    /// - Parameter index: The index of the entry (must be 0..<128)
    /// - Returns: The entry at the specified index
    subscript(index: Int) -> KeyValueEntry<Value> {
        get {
            precondition(index >= 0 && index < 128, "Index out of bounds")
            return withUnsafeBytes(of: storage) { ptr in
                ptr.bindMemory(to: KeyValueEntry<Value>.self)[index]
            }
        }
        set {
            precondition(index >= 0 && index < 128, "Index out of bounds")
            withUnsafeMutableBytes(of: &storage) { ptr in
                ptr.bindMemory(to: KeyValueEntry<Value>.self)[index] = newValue
            }
        }
    }

    /// Resets all entries to empty state.
    ///
    /// This method zeroes out the entire storage buffer, effectively marking all entries
    /// as empty and clearing any previously stored data.
    public mutating func reset() {
        _ = withUnsafeMutableBytes(of: &storage) { ptr in
            ptr.initializeMemory(as: UInt8.self, repeating: 0)
        }
    }
}

// MARK: - Errors

/// Errors that can occur during KeyValueStore operations
public enum KeyValueStoreError: Error {
    /// The provided key exceeds the maximum allowed length (64 bytes)
    case keyTooLong
    /// The store has reached its maximum capacity and cannot accept new entries
    case storeFull
    /// The value type's size exceeds the maximum allowed size (1024 bytes)
    case valueTooLarge
}
