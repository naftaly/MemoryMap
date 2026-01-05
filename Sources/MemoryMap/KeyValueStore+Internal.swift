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

/// Default capacity for the key-value store
let KeyValueStoreDefaultCapacity = 256

// MARK: - Private KeyValueStore

extension KeyValueStore {
  @inline(__always)
  func forEachOccupiedEntry(
    in storage: inout KeyValueStoreStorage<Key, Value>,
    _ body: (Key, Value) -> Void
  ) {
    // Access raw entry buffer once to avoid repeated subscript overhead
    storage.entries.withUnsafeEntries { entries, count in
      for i in 0..<count {
        let entry = entries[i]
        if entry.state == .occupied {
          body(entry.key, entry.value)
        }
      }
    }
  }

  @inline(__always)
  func probeSlot(for key: Key, in storage: inout KeyValueStoreStorage<Key, Value>) -> ProbeResult {
    storage.entries.withUnsafeEntries { entries, count in

      let hashes = key.hashes()
      let hash1 = hashes.0
      let step = hashes.1
      let startIndex = hash1 & (count - 1)
      var index = startIndex
      var probeCount = 0
      var firstTombstoneIndex: Int?

      while probeCount < count {
        let entry = entries[index]

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
        index = (index &+ step) & (count - 1)
      }

      if let tombstoneIndex = firstTombstoneIndex {
        return .available(tombstoneIndex)
      }

      return .full
    }
  }

  func _setValue(_ value: Value?, for key: Key) throws {
    try memoryMap.withLockedStorage { storage in
      switch self.probeSlot(for: key, in: &storage) {
      case .found(let index):
        storage.entries.withUnsafeMutableEntries { entries, _ in
          if let value {
            entries[index].value = value
          } else {
            entries[index].state = .tombstone
          }
        }
      case .available(let index):
        if let value {
          storage.entries.withUnsafeMutableEntries { entries, _ in
            entries[index] = KeyValueEntry(
              key: key,
              value: value,
              state: .occupied
            )
          }
        }
      case .full:
        if value != nil {
          throw KeyValueStoreError.storeFull
        }
      }
    }
  }

  func _value(for key: Key) -> Value? {
    memoryMap.withLockedStorage { storage in
      guard case .found(let index) = self.probeSlot(for: key, in: &storage) else {
        return nil
      }
      return storage.entries.withUnsafeEntries { entries, _ in
        entries[index].value
      }
    }
  }

  func compactInternal(storage: inout KeyValueStoreStorage<Key, Value>) {
    // Collect all active entries
    var activeEntries: [(key: Key, value: Value)] = []

    // Access raw entry buffer once to avoid repeated subscript overhead
    storage.entries.withUnsafeEntries { entries, count in
      for i in 0..<count {
        let entry = entries[i]
        if entry.state == .occupied {
          activeEntries.append((key: entry.key, value: entry.value))
        }
      }
    }

    // Clear the entire table
    storage.entries.reset()

    // Reinsert all entries with fresh hash positions using double hashing
    storage.entries.withUnsafeMutableEntries { entries, count in

      for (key, value) in activeEntries {
        let hashes = key.hashes()
        let hash1 = hashes.0
        let step = hashes.1
        var index = hash1 & (count - 1)
        var probeCount = 0

        // Find the first empty slot (no tombstones after clearing)
        var inserted = false
        while probeCount < count {
          let entry = entries[index]
          if entry.state == .empty {
            entries[index] = KeyValueEntry(
              key: key,
              value: value,
              state: .occupied
            )
            inserted = true
            break
          }
          // Double hashing: increment by step (eliminates multiplication)
          probeCount += 1
          index = (index &+ step) & (count - 1)
        }

        // This should never fail since we just cleared the table and are reinserting
        // the same number of entries, but guard against data loss
        precondition(inserted, "Failed to reinsert entry during compaction")
      }
    }
  }

  /// The number of key-value pairs in the store (calculated on-demand)
  var count: Int {
    memoryMap.withLockedStorage { storage in
      var result = 0
      storage.entries.withUnsafeEntries { entries, count in
        for i in 0..<count {
          if entries[i].state == .occupied {
            result += 1
          }
        }
      }
      return result
    }
  }

  /// A Boolean value indicating whether the store is empty (calculated on-demand)
  var isEmpty: Bool {
    memoryMap.withLockedStorage { storage in
      storage.entries.withUnsafeEntries { entries, count in
        for i in 0..<count {
          if entries[i].state == .occupied {
            return false
          }
        }
        return true
      }
    }
  }
}

enum ProbeResult {
  case found(Int)
  case available(Int)
  case full
}

// MARK: - POD Types

/// Storage container for the key-value store.
///
/// This structure holds the hash table entries.
/// It is designed to be a POD (Plain Old Data) type for efficient memory-mapped storage.
struct KeyValueStoreStorage<Key: BasicTypeCompliance, Value: BitwiseCopyable> {
  /// Fixed-size array of hash table entries
  var entries: KeyValueStoreEntries<Key, Value>
}

/// A single entry in the key-value store.
///
/// Each entry contains a key, value, and state indicator. This structure is designed
/// to be a POD type for efficient memory-mapped storage in a hash table using double hashing.
struct KeyValueEntry<Key: BasicTypeCompliance, Value: BitwiseCopyable> {
  /// The key for this entry
  var key: Key
  /// The value stored in this entry
  var value: Value

  /// State of a slot in the key-value store
  enum SlotState: UInt8, BitwiseCopyable {
    /// Never used or fully cleared
    case empty = 0
    /// Contains a valid key-value pair
    case occupied = 1
    /// Previously occupied but deleted (maintains probe chains for double hashing)
    case tombstone = 2
  }

  /// The current state of this hash table slot
  var state: SlotState

  init(key: Key, value: Value, state: SlotState) {
    self.key = key
    self.value = value
    self.state = state
  }
}

/// Fixed-size array of 256 entries with subscript access.
///
/// This structure provides a fixed-capacity hash table storage using a tuple for the
/// underlying representation. The tuple ensures the struct remains a POD type, which is
/// required for safe memory-mapped storage.
struct KeyValueStoreEntries<Key: BasicTypeCompliance, Value: BitwiseCopyable> {
  /// Tuple-based storage for 256 entries (ensures POD/trivial type for memory mapping)
  private var storage:
    (
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,

      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,

      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,

      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,

      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,

      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,

      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,

      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,

      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>, KeyValueEntry<Key, Value>,
      KeyValueEntry<Key, Value>
    )

  mutating func withUnsafeMutableEntries(
    _ block: (UnsafeMutableBufferPointer<KeyValueEntry<Key, Value>>, Int)
      -> Void
  ) {
    withUnsafeMutableBytes(of: &storage) { ptr in
      let entries = ptr.bindMemory(to: KeyValueEntry<Key, Value>.self)
      block(entries, KeyValueStoreDefaultCapacity)
    }
  }

  func withUnsafeEntries<Result>(
    _ block: (UnsafeBufferPointer<KeyValueEntry<Key, Value>>, Int) -> Result
  ) -> Result {
    withUnsafeBytes(of: storage) { ptr in  // No & here
      let entries = ptr.bindMemory(to: KeyValueEntry<Key, Value>.self)
      return block(entries, KeyValueStoreDefaultCapacity)
    }
  }

  /// Resets all entries to empty state.
  ///
  /// This method zeroes out the entire storage buffer, effectively marking all entries
  /// as empty and clearing any previously stored data.
  mutating func reset() {
    _ = withUnsafeMutableBytes(of: &storage) { ptr in
      ptr.initializeMemory(as: UInt8.self, repeating: 0)
    }
  }
}
