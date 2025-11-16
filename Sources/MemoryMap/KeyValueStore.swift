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
    private let capacity: Int

    /// The URL of the memory-mapped file backing this store
    public var url: URL {
        return memoryMap.url
    }

    /// The number of key-value pairs in the store
    public var count: Int {
        return memoryMap.get { storage in
            var count = 0
            for i in 0..<self.capacity {
                if self.getEntry(from: &storage, at: i).occupied {
                    count += 1
                }
            }
            return count
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
            for i in 0..<self.capacity {
                let entry = self.getEntry(from: &storage, at: i)
                if entry.occupied {
                    if let key = self.keyToString(entry.key) {
                        keys.append(key)
                    }
                }
            }
            return keys
        }
    }

    /// Accesses the value associated with the given key for reading and writing.
    ///
    /// When you assign a value for a key and that key already exists, the store
    /// overwrites the existing value. If the store doesn't have enough capacity,
    /// the assignment is silently ignored.
    ///
    /// When you access a key that isn't present, the result is nil.
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
    ///   - capacity: Maximum number of entries (default: 128, max: 128)
    ///   - maxValueSize: Maximum allowed size for the Value type in bytes (default: 1KB).
    ///                   This is a safety limit to prevent accidentally using large structs as values.
    ///
    /// - Note: The capacity is fixed at initialization and cannot be changed later.
    ///         Maximum capacity is currently limited to 128 entries.
    public init(fileURL: URL, capacity: Int = KeyValueStoreDefaultCapacity, maxValueSize: Int = KeyValueStoreDefaultMaxValueSize) throws {
        guard capacity <= KeyValueStoreDefaultCapacity && capacity > 0 else {
            throw KeyValueStoreError.invalidCapacity
        }
        guard MemoryLayout<Value>.stride <= maxValueSize else {
            throw KeyValueStoreError.valueTooLarge
        }
        self.capacity = capacity
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
        guard let keyBytes = key.data(using: .utf8), keyBytes.count <= KeyValueStoreMaxKeyLength else {
            throw KeyValueStoreError.keyTooLong
        }

        try memoryMap.get { storage in
            var keyArray = KeyValueStoreKey()
            for i in 0..<keyBytes.count {
                keyArray[i] = Int8(bitPattern: keyBytes[i])
            }

            let hash = self.hashKey(keyArray)
            var index = hash % self.capacity
            var probeCount = 0

            // Linear probing to find empty slot or existing key
            while probeCount < self.capacity {
                let entry = self.getEntry(from: &storage, at: index)

                if !entry.occupied {
                    // Found empty slot
                    self.setEntry(in: &storage, at: index, entry: KeyValueEntry(
                        key: keyArray,
                        value: value,
                        occupied: true
                    ))
                    return
                } else if self.keysEqual(entry.key, keyArray) {
                    // Found existing key, update value
                    var updatedEntry = entry
                    updatedEntry.value = value
                    self.setEntry(in: &storage, at: index, entry: updatedEntry)
                    return
                }

                index = (index + 1) % self.capacity
                probeCount += 1
            }

            throw KeyValueStoreError.storeFull
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
        guard let keyBytes = key.data(using: .utf8), keyBytes.count <= KeyValueStoreMaxKeyLength else {
            throw KeyValueStoreError.keyTooLong
        }

        return try memoryMap.get { storage in
            var keyArray = KeyValueStoreKey()
            for i in 0..<keyBytes.count {
                keyArray[i] = Int8(bitPattern: keyBytes[i])
            }

            let hash = self.hashKey(keyArray)
            var index = hash % self.capacity
            var probeCount = 0

            // Linear probing to find empty slot or existing key
            while probeCount < self.capacity {
                let entry = self.getEntry(from: &storage, at: index)

                if !entry.occupied {
                    // Found empty slot
                    self.setEntry(in: &storage, at: index, entry: KeyValueEntry(
                        key: keyArray,
                        value: value,
                        occupied: true
                    ))
                    return nil
                } else if self.keysEqual(entry.key, keyArray) {
                    // Found existing key, update value
                    let oldValue = entry.value
                    var updatedEntry = entry
                    updatedEntry.value = value
                    self.setEntry(in: &storage, at: index, entry: updatedEntry)
                    return oldValue
                }

                index = (index + 1) % self.capacity
                probeCount += 1
            }

            throw KeyValueStoreError.storeFull
        }
    }

    /// Removes the given key and its associated value from the store.
    ///
    /// - Parameter key: The key to remove along with its associated value
    /// - Returns: The value that was removed, or nil if the key was not present
    @discardableResult
    public func removeValue(forKey key: String) -> Value? {
        guard let keyBytes = key.data(using: .utf8), keyBytes.count <= KeyValueStoreMaxKeyLength else {
            return nil
        }

        return memoryMap.get { storage in
            var keyArray = KeyValueStoreKey()
            for i in 0..<keyBytes.count {
                keyArray[i] = Int8(bitPattern: keyBytes[i])
            }

            let hash = self.hashKey(keyArray)
            var index = hash % self.capacity
            var probeCount = 0

            while probeCount < self.capacity {
                var entry = self.getEntry(from: &storage, at: index)

                if !entry.occupied {
                    return nil
                } else if self.keysEqual(entry.key, keyArray) {
                    // Mark as unoccupied and return the old value
                    let oldValue = entry.value
                    entry.occupied = false
                    self.setEntry(in: &storage, at: index, entry: entry)
                    return oldValue
                }

                index = (index + 1) % self.capacity
                probeCount += 1
            }

            return nil
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
            for i in 0..<self.capacity {
                var entry = self.getEntry(from: &storage, at: i)
                entry.occupied = false
                self.setEntry(in: &storage, at: i, entry: entry)
            }
        }
    }

    /// Returns a standard Swift Dictionary containing all key-value pairs from the store.
    ///
    /// This creates a copy of the data, allowing you to use all Dictionary methods
    /// and collection operations.
    ///
    /// - Returns: A Dictionary with all keys and values from the store
    public func toDictionary() -> [String: Value] {
        var dict: [String: Value] = [:]
        dict.reserveCapacity(count)
        for key in keys {
            if let value = self[key] {
                dict[key] = value
            }
        }
        return dict
    }

    // MARK: - Private Helpers

    private func get(_ key: String) -> Value? {
        guard let keyBytes = key.data(using: .utf8), keyBytes.count <= KeyValueStoreMaxKeyLength else {
            return nil
        }

        return memoryMap.get { storage in
            var keyArray = KeyValueStoreKey()
            for i in 0..<keyBytes.count {
                keyArray[i] = Int8(bitPattern: keyBytes[i])
            }

            let hash = self.hashKey(keyArray)
            var index = hash % self.capacity
            var probeCount = 0

            while probeCount < self.capacity {
                let entry = self.getEntry(from: &storage, at: index)

                if !entry.occupied {
                    return nil
                } else if self.keysEqual(entry.key, keyArray) {
                    return entry.value
                }

                index = (index + 1) % self.capacity
                probeCount += 1
            }

            return nil
        }
    }

    private func getEntry(from storage: inout KeyValueStoreStorage<Value>, at index: Int) -> KeyValueEntry<Value> {
        return storage.entries[index]
    }

    private func setEntry(in storage: inout KeyValueStoreStorage<Value>, at index: Int, entry: KeyValueEntry<Value>) {
        storage.entries[index] = entry
    }

    private func hashKey(_ key: KeyValueStoreKey) -> Int {
        var hash = 5381
        for i in 0..<KeyValueStoreMaxKeyLength {
            let byte = key[i]
            if byte == 0 { break }
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }

    private func keysEqual(_ key1: KeyValueStoreKey, _ key2: KeyValueStoreKey) -> Bool {
        for i in 0..<KeyValueStoreMaxKeyLength {
            if key1[i] != key2[i] {
                return false
            }
        }
        return true
    }

    private func keyToString(_ key: KeyValueStoreKey) -> String? {
        // Find the null terminator
        var length = 0
        while length < KeyValueStoreMaxKeyLength && key[length] != 0 {
            length += 1
        }
        var data = Data(count: length)
        for i in 0..<length {
            data[i] = UInt8(bitPattern: key[i])
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - POD Types

/// Storage container for the key-value store
@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct KeyValueStoreStorage<Value> {
    public var entries: KeyValueStoreEntries<Value>
}

/// Fixed-size byte array (64 bytes) with subscript access
@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct FixedByteArray64 {
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

    /// Default initializer - creates a zero-filled array
    public init() {
        self.storage = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
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

/// Fixed-size key storage (64 bytes)
@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct KeyValueStoreKey {
    public var bytes: FixedByteArray64

    /// Default initializer - creates a zero-filled key
    public init() {
        self.bytes = FixedByteArray64()
    }

    /// Convenience subscript that delegates to bytes
    public subscript(index: Int) -> Int8 {
        get { bytes[index] }
        set { bytes[index] = newValue }
    }
}

/// A single entry in the key-value store
@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct KeyValueEntry<Value> {
    var key: KeyValueStoreKey
    var value: Value
    var occupied: Bool

    init(key: KeyValueStoreKey = KeyValueStoreKey(), value: Value, occupied: Bool = false) {
        self.key = key
        self.value = value
        self.occupied = occupied
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
}

// MARK: - Errors

public enum KeyValueStoreError: Error {
    case keyTooLong
    case storeFull
    case invalidCapacity
    case valueTooLarge
}
