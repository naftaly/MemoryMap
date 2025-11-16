
# Welcome to MemoryMap! 🚀

[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey.svg)]()

MemoryMap is a Swift utility class designed for efficient persistence and crash-resilient storage of Plain Old Data (POD) structs using memory-mapped files. It provides thread-safe access to the stored data, ensuring integrity and performance for applications requiring low-latency storage solutions.

## Features

- **Memory-mapped file support**: Back a POD struct with a memory-mapped file for direct memory access
- **Thread-safe access**: Read and write operations protected by NSLock
- **Crash resilience**: Changes immediately reflected in the memory-mapped file
- **Data integrity validation**: File validation using magic numbers
- **KeyValueStore**: High-performance hash table with Dictionary-like API (10-20μs per operation)
- **Main-thread safe**: All operations optimized for UI thread usage
- **Double hashing**: Eliminates clustering for consistent performance even at high load factors

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

// Closure-based access with lock
memoryMap.withLockedStorage { storage in
    storage.counter += 1
    storage.flag = !storage.flag
}
```

### KeyValueStore - High-Performance Hash Table

```swift
import MemoryMap

struct UserData {
    var lastSeen: Double
    var loginCount: Int
}

let store = try KeyValueStore<UserData>(fileURL: fileURL)

// Dictionary-like subscript access
store["user:123"] = UserData(lastSeen: Date().timeIntervalSince1970, loginCount: 1)

// Read with default value
let data = store["user:456", default: UserData(lastSeen: 0, loginCount: 0)]

// Explicit error handling
try store.setValue(
    UserData(lastSeen: Date().timeIntervalSince1970, loginCount: 5),
    for: "user:123"
)

// Iterate over keys
for key in store.keys {
    if let value = store[key] {
        print("\(key): \(value.loginCount) logins")
    }
}

// Compact to remove tombstones and improve performance
store.compact()

// Convert to Dictionary for advanced operations
let dict = store.dictionaryRepresentation()
```

## Performance

KeyValueStore uses **double hashing** with optimized comparisons for excellent main-thread performance:

| Operation | Time (100 ops) | Per-Op | Main Thread |
|-----------|----------------|--------|-------------|
| Insert | 1.0ms | 10 μs | ✅ Excellent |
| Lookup (hit) | 1.0ms | 10 μs | ✅ Excellent |
| Lookup (miss) | 2.0ms | 20 μs | ✅ Excellent |
| Update | 2.0ms | 20 μs | ✅ Excellent |
| Remove | 3.0ms | 15 μs | ✅ Excellent |

**Load Factor Performance:**
- 25% load: 17ms (baseline)
- 50% load: 35ms (2.1x)
- 75% load: 57ms (3.4x)
- 99% load: 106ms (6.2x) ⚠️

**Main Thread Budget:**
- 60fps: 16.67ms per frame
- 120fps: 8.33ms per frame

All operations are well within budget for smooth UI performance. Even at 99% capacity, performance remains acceptable for main thread usage.

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
