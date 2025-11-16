/// MIT License
///
/// Copyright (c) 2024 Alexander Cohen
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

/// A key-value store backed by MemoryMap that supports string keys and POD values.
///
/// The store uses a hash table with linear probing for collision resolution.
/// All data is persisted to disk via memory-mapped files, providing crash resilience.
///
/// The API is similar to Swift's Dictionary, with subscript access and familiar methods.
///
/// Example:
/// ```swift
/// struct MyValue {
///     var counter: Int
///     var timestamp: Double
/// }
///
/// let store = try KeyValueStore<MyValue>(fileURL: url, capacity: 128)
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
/// // Update and get old value
/// let oldValue = try store.updateValue(MyValue(counter: 2, timestamp: Date().timeIntervalSince1970), forKey: "user:123")
///
/// // Iterate over keys
/// for key in store.keys {
///     print("Key: \(key)")
/// }
///
/// // Check count and emptiness
/// print("Store has \(store.count) items")
/// if !store.isEmpty {
///     print("Store is not empty")
/// }
/// ```
@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public class KeyValueStore<Value> {

    private let memoryMap: MemoryMap<KeyValueStoreStorage<Value>>

    /// The URL of the memory-mapped file backing this store
    public var url: URL {
        return memoryMap.url
    }

    /// The number of key-value pairs in the store
    public var count: Int {
        return memoryMap.get { storage in
            return storage.count
        }
    }

    /// A Boolean value indicating whether the store is empty
    public var isEmpty: Bool {
        return count == 0
    }

    /// A collection containing just the keys of the store
    public var keys: [String] {
        return memoryMap.get { storage in
            var keys: [String] = []
            self.forEachOccupiedEntry(in: &storage) { key, _ in
                keys.append(key)
            }
            return keys
        }
    }

    /// Accesses the value associated with the given key for reading and writing.
    ///
    /// When you assign a value for a key and that key already exists, the store
    /// overwrites the existing value.
    ///
    /// When you access a key that isn't present, the result is nil.
    ///
    /// - Note: Setting a value silently fails (no error is thrown) if:
    ///   - The key is longer than 64 bytes (in UTF-8 encoding)
    ///   - The store is at capacity and the key doesn't already exist
    ///   For throwing versions that report errors, use `set(_:_:)` or `updateValue(_:forKey:)`.
    public subscript(key: String) -> Value? {
        get {
            return get(key)
        }
        set {
            if let value = newValue {
                _ = try? self.set(key, value)
            } else {
                _ = self.removeValue(forKey: key)
            }
        }
    }

    /// Accesses the value with the given key, falling back to the default value if the key isn't found.
    public subscript(key: String, default defaultValue: @autoclosure () -> Value) -> Value {
        return get(key) ?? defaultValue()
    }

    /// Initializes a key-value store with the specified capacity.
    ///
    /// - Parameters:
    ///   - fileURL: The file location for the memory-mapped store
    ///
    /// - Note: The capacity is fixed at initialization and cannot be changed later.
    ///         Maximum capacity is currently limited to 128 entries.
    public init(fileURL: URL) throws {
        guard MemoryLayout<Value>.stride <= KeyValueStoreDefaultMaxValueSize else {
            throw KeyValueStoreError.valueTooLarge
        }
        self.memoryMap = try MemoryMap<KeyValueStoreStorage<Value>>(fileURL: fileURL)
    }

    /// Sets a value for the given key.
    ///
    /// If the key already exists, its value is updated. If the store is full,
    /// this method throws an error.
    ///
    /// - Parameters:
    ///   - key: The string key (max 64 bytes UTF-8)
    ///   - value: The POD value to store
    ///
    /// - Throws: `KeyValueStoreError.keyTooLong` if key exceeds max length
    ///           `KeyValueStoreError.storeFull` if capacity is reached
    public func set(_ key: String, _ value: Value) throws {
        let keyArray = try stringToKeyArray(key)

        try memoryMap.get { storage in
            switch self.probeSlot(for: keyArray, in: &storage) {
            case .found(let index):
                var updatedEntry = self.getEntry(from: &storage, at: index)
                updatedEntry.value = value
                self.setEntry(in: &storage, at: index, entry: updatedEntry)
            case .available(let index):
                self.setEntry(in: &storage, at: index, entry: KeyValueEntry(
                    key: keyArray,
                    value: value,
                    occupied: true,
                    tombstone: false
                ))
                storage.count += 1
            case .full:
                throw KeyValueStoreError.storeFull
            }
        }
    }

    /// Updates the value stored in the store for the given key, or adds a new key-value pair if the key does not exist.
    ///
    /// - Parameters:
    ///   - value: The new value to store
    ///   - key: The key to associate with value
    /// - Returns: The value that was replaced, or nil if a new key-value pair was added
    /// - Throws: `KeyValueStoreError.keyTooLong` if key exceeds max length
    ///           `KeyValueStoreError.storeFull` if capacity is reached
    @discardableResult
    public func updateValue(_ value: Value, forKey key: String) throws -> Value? {
        let keyArray = try stringToKeyArray(key)

        return try memoryMap.get { storage in
            switch self.probeSlot(for: keyArray, in: &storage) {
            case .found(let index):
                let entry = self.getEntry(from: &storage, at: index)
                let oldValue = entry.value
                var updatedEntry = entry
                updatedEntry.value = value
                self.setEntry(in: &storage, at: index, entry: updatedEntry)
                return oldValue
            case .available(let index):
                self.setEntry(in: &storage, at: index, entry: KeyValueEntry(
                    key: keyArray,
                    value: value,
                    occupied: true,
                    tombstone: false
                ))
                storage.count += 1
                return nil
            case .full:
                throw KeyValueStoreError.storeFull
            }
        }
    }

    /// Removes the given key and its associated value from the store.
    ///
    /// - Parameter key: The key to remove along with its associated value
    /// - Returns: The value that was removed, or nil if the key was not present
    @discardableResult
    public func removeValue(forKey key: String) -> Value? {
        guard let keyArray = try? stringToKeyArray(key) else {
            return nil
        }

        return memoryMap.get { storage in
            guard case let .found(index) = self.probeSlot(for: keyArray, in: &storage) else {
                return nil
            }

            var entry = self.getEntry(from: &storage, at: index)
            let oldValue = entry.value
            entry.occupied = false
            entry.tombstone = true
            self.setEntry(in: &storage, at: index, entry: entry)
            storage.count -= 1
            return oldValue
        }
    }

    /// Returns a Boolean value indicating whether the store contains the given key.
    ///
    /// - Parameter key: The key to check
    /// - Returns: true if the key exists, false otherwise
    public func contains(_ key: String) -> Bool {
        return self[key] != nil
    }

    /// Removes all entries from the store.
    public func removeAll() {
        memoryMap.get { storage in
            storage.entries.reset()
            storage.count = 0
        }
    }

    /// Returns a standard Swift Dictionary containing all key-value pairs from the store.
    ///
    /// This creates a copy of the data, allowing you to use all Dictionary methods
    /// and collection operations.
    ///
    /// - Returns: A Dictionary with all keys and values from the store
    public func toDictionary() -> [String: Value] {
        return memoryMap.get { storage in
            var dict: [String: Value] = [:]
            dict.reserveCapacity(storage.count)
            self.forEachOccupiedEntry(in: &storage) { key, value in
                dict[key] = value
            }
            return dict
        }
    }

    // MARK: - Private Helpers

    private func stringToKeyArray(_ key: String) throws -> KeyValueStoreKey {
        guard let keyBytes = key.data(using: .utf8), keyBytes.count <= KeyValueStoreMaxKeyLength else {
            throw KeyValueStoreError.keyTooLong
        }
        var keyArray = KeyValueStoreKey()
        keyArray.length = UInt8(keyBytes.count)
        for i in 0..<keyBytes.count {
            keyArray[i] = Int8(bitPattern: keyBytes[i])
        }
        return keyArray
    }

    private func get(_ key: String) -> Value? {
        guard let keyArray = try? stringToKeyArray(key) else {
            return nil
        }

        return memoryMap.get { storage in
            guard case let .found(index) = self.probeSlot(for: keyArray, in: &storage) else {
                return nil
            }
            let entry = self.getEntry(from: &storage, at: index)
            return entry.value
        }
    }

    private func getEntry(from storage: inout KeyValueStoreStorage<Value>, at index: Int) -> KeyValueEntry<Value> {
        return storage.entries[index]
    }

    private func setEntry(in storage: inout KeyValueStoreStorage<Value>, at index: Int, entry: KeyValueEntry<Value>) {
        storage.entries[index] = entry
    }

    private func hashKey(_ key: KeyValueStoreKey) -> Int {
        // djb2 hash algorithm
        var hash = 5381
        let length = self.keyLength(key)
        for i in 0..<length {
            let byte = key[i]
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        // Ensure non-negative result (abs(Int.min) overflows, so use bitwise AND with Int.max)
        return hash & Int.max
    }

    private func keysEqual(_ key1: KeyValueStoreKey, _ key2: KeyValueStoreKey) -> Bool {
        let length1 = self.keyLength(key1)
        let length2 = self.keyLength(key2)
        guard length1 == length2 else {
            return false
        }
        for i in 0..<length1 {
            if key1[i] != key2[i] {
                return false
            }
        }
        return true
    }

    private func keyToString(_ key: KeyValueStoreKey) -> String? {
        let length = self.keyLength(key)
        guard length <= KeyValueStoreMaxKeyLength else {
            return nil
        }
        var data = Data(count: length)
        for i in 0..<length {
            data[i] = UInt8(bitPattern: key[i])
        }
        return String(data: data, encoding: .utf8)
    }

    private func keyLength(_ key: KeyValueStoreKey) -> Int {
        return Int(key.length)
    }

    private func probeSlot(for key: KeyValueStoreKey, in storage: inout KeyValueStoreStorage<Value>) -> ProbeResult {
        let hash = self.hashKey(key)
        var index = hash % KeyValueStoreDefaultCapacity
        var probeCount = 0
        var firstTombstoneIndex: Int?

        while probeCount < KeyValueStoreDefaultCapacity {
            let entry = self.getEntry(from: &storage, at: index)

            if entry.occupied && !entry.tombstone {
                if self.keysEqual(entry.key, key) {
                    return .found(index)
                }
            } else if entry.tombstone {
                if firstTombstoneIndex == nil {
                    firstTombstoneIndex = index
                }
            } else {
                return .available(firstTombstoneIndex ?? index)
            }

            index = (index + 1) % KeyValueStoreDefaultCapacity
            probeCount += 1
        }

        if let tombstoneIndex = firstTombstoneIndex {
            return .available(tombstoneIndex)
        }

        return .full
    }

    private func forEachOccupiedEntry(in storage: inout KeyValueStoreStorage<Value>, _ body: (String, Value) -> Void) {
        for i in 0..<KeyValueStoreDefaultCapacity {
            let entry = self.getEntry(from: &storage, at: i)
            if entry.occupied && !entry.tombstone, let key = self.keyToString(entry.key) {
                body(key, entry.value)
            }
        }
    }
}

private enum ProbeResult {
    case found(Int)
    case available(Int)
    case full
}

// MARK: - POD Types

/// Storage container for the key-value store
@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct KeyValueStoreStorage<Value> {
    public var entries: KeyValueStoreEntries<Value>
    public var count: Int  // Number of active entries (not tombstones)
}

/// Fixed-size key storage (64 bytes) plus tracked length
@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct KeyValueStoreKey {
    // Public storage ensures the struct remains trivial/POD
    public var storage: (
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8
    )
    public var length: UInt8

    /// Default initializer - creates a zero-filled key
    public init() {
        self.storage = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
        self.length = 0
    }

    /// Subscript for byte access
    public subscript(index: Int) -> Int8 {
        get {
            precondition(index >= 0 && index < 64, "Index out of bounds")
            return withUnsafeBytes(of: storage) { ptr in
                Int8(bitPattern: ptr[index])
            }
        }
        set {
            precondition(index >= 0 && index < 64, "Index out of bounds")
            withUnsafeMutableBytes(of: &storage) { ptr in
                ptr[index] = UInt8(bitPattern: newValue)
            }
        }
    }
}

/// A single entry in the key-value store
@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct KeyValueEntry<Value> {
    var key: KeyValueStoreKey
    var value: Value
    var occupied: Bool
    var tombstone: Bool  // Marks deleted entries to maintain probe chains

    init(key: KeyValueStoreKey = KeyValueStoreKey(), value: Value, occupied: Bool = false, tombstone: Bool = false) {
        self.key = key
        self.value = value
        self.occupied = occupied
        self.tombstone = tombstone
    }
}

/// Fixed-size array of 128 entries with subscript access
@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct KeyValueStoreEntries<Value> {
    // Public storage ensures the struct remains trivial/POD
    public var storage: (
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

    /// Subscript for clean array-like access
    public subscript(index: Int) -> KeyValueEntry<Value> {
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

    /// Zeroes the entire storage, marking every entry as empty.
    public mutating func reset() {
        _ = withUnsafeMutableBytes(of: &storage) { ptr in
            ptr.initializeMemory(as: UInt8.self, repeating: 0)
        }
    }
}

// MARK: - Errors

public enum KeyValueStoreError: Error {
    case keyTooLong
    case storeFull
    case valueTooLarge
}
