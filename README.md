
# MemoryMap

[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20macOS%2013%2B%20%7C%20tvOS%2016%2B%20%7C%20watchOS%209%2B%20%7C%20visionOS%202%2B-lightgrey.svg)]()

A Swift library for crash-resilient, memory-mapped file storage. Provides direct file-backed persistence with thread-safe access and microsecond-latency operations.

## Requirements

- Swift 6.0+
- macOS 13.0+ / iOS 16.0+ / tvOS 16.0+ / watchOS 9.0+ / visionOS 2.0+

## Features

- **Direct file-backed storage**: Memory-mapped POD structs with crash resilience
- **Thread-safe**: Configurable locking (OSAllocatedUnfairLock, NoLock, NSLock, or custom)
- **KeyValueStore**: 256-entry hash table with Dictionary-like API
- **Fast lookups**: ~11-12μs per operation, consistent at all load factors
- **Type-safe**: BasicType wrappers for Int, String, Double, Bool
- **Main-thread safe**: Microsecond operations suitable for UI thread

## Installation

To get started with MemoryMap, integrate it directly into your project:

1. In Xcode, select **File** > **Swift Packages** > **Add Package Dependency...**
2. Enter the repository URL `https://github.com/naftaly/memorymap.git`.
3. Specify the version or branch you want to use.
4. Follow the prompts to complete the integration.

## Usage

### MemoryMap - Direct POD Storage

```swift
import MemoryMap

struct MyData {
    var counter: Int
    var flag: Bool
}

let fileURL = URL(fileURLWithPath: "/path/to/memory.map")
let memoryMap = try MemoryMap<MyData>(fileURL: fileURL)

// Direct property access
memoryMap.get.counter = 42
memoryMap.get.flag = true

// Batch operations with closure
memoryMap.withLockedStorage { storage in
    storage.counter += 1
    storage.flag = !storage.flag
}
```

### BasicType Sizes

MemoryMap provides three size variants for type-safe storage:

- **BasicType8** (alias: `BasicTypeNumber`): 10 bytes total
  - Optimized for numeric types (Int, UInt, Double, Float, Bool)
  - Minimal memory footprint for compact keys or values

- **BasicType64**: 62 bytes total
  - Suitable for short strings (~60 characters)
  - Good balance between size and flexibility

- **BasicType1024**: 1022 bytes total
  - For longer strings (~1000 characters)
  - Use when you need to store larger text values

```swift
// Compact numeric storage
let numericStore = try KeyValueStore<BasicTypeNumber, UserData>(fileURL: url)
numericStore[12345] = userData  // Integer literal works directly

// General purpose with short strings
let generalStore = try KeyValueStore<BasicType64, BasicType64>(fileURL: url)
generalStore["user:123"] = 42  // String and integer literals work

// Large string storage
let largeStore = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)
largeStore["config"] = "very long configuration string..."
```

### KeyValueStore - High-Performance Hash Table

```swift
import MemoryMap

struct UserData {
    var lastSeen: Double
    var loginCount: Int
}

let fileURL = URL(fileURLWithPath: "/path/to/store.map")
let store = try KeyValueStore<BasicType64, UserData>(fileURL: fileURL)

// Set values using dictionary-like subscript
store["user:123"] = UserData(lastSeen: Date().timeIntervalSince1970, loginCount: 1)

// Read with default value
let data = store["user:456", default: UserData(lastSeen: 0, loginCount: 0)]

// Iterate over all entries
for key in store.keys {
    if let value = store[key] {
        print("\(key): \(value.loginCount) logins")
    }
}

// Remove tombstones to improve performance
store.compact()
```

### Advanced: Custom Locks

Both MemoryMap and KeyValueStore support custom lock implementations for specialized use cases:

```swift
// Single-threaded (no locking overhead)
let store = try KeyValueStore<BasicType64, UserData>(fileURL: url, lock: NoLock())

// Use NSLock instead of OSAllocatedUnfairLock
let store = try KeyValueStore<BasicType64, UserData>(fileURL: url, lock: NSLock())

// Default (OSAllocatedUnfairLock)
let store = try KeyValueStore<BasicType64, UserData>(fileURL: url)
```

## Performance

*Benchmarks measured on Apple M3, 24 GB RAM, macOS 15.1*

**KeyValueStore:**
- **Lookup speed:** ~11-12μs per lookup, consistent across all load factors (25%-99%)
- **Insert/Update:** ~10-20μs per operation
- **Capacity:** 256 entries, recommended ≤200 keys for optimal performance (~78% load)
- **Memory footprint:** ~306 KB per store (BasicType64 + BasicType1024)
- **Main thread safe:** Well within 60fps budget (<2.5ms for 200 lookups)
- **Load factor performance:** Remains consistent even at 99% capacity due to efficient double hashing

**Load Factor Benchmarks (10,000+ lookups):**
- 25% load (64 keys): ~11.4μs per lookup
- 50% load (128 keys): ~11.6μs per lookup
- 75% load (192 keys): ~11.6μs per lookup
- 90% load (230 keys): ~11.6μs per lookup
- 99% load (253 keys): ~12.1μs per lookup

**BasicType operations:**
- Int/Double/Bool: Sub-microsecond
- Hashing/equality checks: ~0.5μs

## Development

### Code Formatting

This project uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) for consistent code style:

```bash
# Install SwiftFormat
brew install swiftformat

# Format all code
swiftformat Sources/ Tests/

# Configuration is in .swiftformat
```

### Running Tests

```bash
# Run all tests
swift test

# Run with sanitizers
swift test --sanitize thread     # Thread Sanitizer
swift test --sanitize address    # Address Sanitizer
swift test --sanitize undefined  # Undefined Behavior Sanitizer

# Run only performance benchmarks
swift test --filter testPerformance
```

### Benchmarks

Performance benchmarks run automatically on PRs and pushes to main via GitHub Actions. Results are posted as comments on PRs.

## Contributing

Got ideas on how to make MemoryMap even better? We'd love to hear from you! Feel free to fork the repo, push your changes, and open a pull request. You can also open an issue if you run into bugs or have feature suggestions.

## License

MemoryMap is proudly open-sourced under the MIT License. Dive into the LICENSE file for more details.
