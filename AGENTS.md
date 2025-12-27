# AGENTS.md

This file provides guidance for AI coding agents working in this repository.

**Note:** Keep this file up to date as you work. Add new findings, architectural insights, gotchas, or patterns you discover. Fix any errors or outdated information. This is a living document that should evolve with the codebase.

## Project Overview

MemoryMap is a Swift library for crash-resilient, memory-mapped file storage of Plain Old Data (POD) types. It provides two main components:

1. **MemoryMap<T>** - Direct memory-mapped storage for POD structs
2. **KeyValueStore<Key, Value>** - High-performance hash table with 256 fixed-capacity entries using double hashing

**Key constraint:** All stored types must be POD (Plain Old Data) - structs containing only trivial types with no references or object pointers. This is required for safe memory-mapped file persistence.

## Architecture

### Core Components

**MemoryMap.swift** - Memory-mapped file wrapper
- Uses `mmap()` with `MAP_SHARED` for direct file-backed storage
- Thread-safe via configurable lock (default: `OSAllocatedUnfairLock`)
- Magic number validation (0xB10C) for file integrity
- Maximum file size: 1MB
- Provides `withLockedStorage` (safe) and `withUnsafeStorage` (manual locking) APIs
- Accepts custom lock via `lock:` parameter in initializer

**Locks.swift** - Lock abstraction layer
- `MemoryMapLock` protocol: Common interface for lock implementations
- `DefaultMemoryMapLock`: Type alias for `OSAllocatedUnfairLock` (default)
- `NoLock`: Zero-cost no-op lock for single-threaded use cases
- `NSLock`: Standard Foundation lock (via protocol conformance)
- Allows custom lock implementations for specialized needs

**KeyValueStore.swift** - Hash table implementation
- **Fixed capacity:** 256 entries (power of 2 for efficient modulo via bitwise AND)
- **Collision resolution:** Double hashing with FNV-1a hash1 and derived hash2
- **Tombstone handling:** Deleted entries leave tombstones; call `compact()` to remove
- **Storage layout:** Tuple-based fixed array (`KeyValueStoreEntries`) to maintain POD compliance
- **Performance:** ~11-12μs per lookup, consistent across all load factors up to 99%

**BasicType.swift** - Type-safe value wrapper
- `BasicType8` (alias: `BasicTypeNumber`): 8 bytes storage + 3 bytes metadata = 10 bytes packed (stride: 10 bytes)
- `BasicType64`: 60 bytes storage + 3 bytes metadata = 62 bytes packed (stride: 62 bytes)
- `BasicType1024`: 1020 bytes storage + 3 bytes metadata = 1022 bytes packed (stride: 1022 bytes)
- Stores: Int, UInt, Float, Double, Bool, String (length-limited)
- Uses `@inline(__always)` for performance-critical paths
- **Double hashing:** `hashes()` returns `(hash1, hash2)` where hash2 is guaranteed odd

**ByteStorage.swift** - Fixed-size POD storage
- Uses tuples instead of arrays to maintain trivial type guarantee
- Uses `UnsafeRawPointer` for extraction to avoid buffer bounds checking overhead
- `ByteStorage8`: 8-byte tuple of Int8 (minimal storage for numeric types)
- `ByteStorage60`: 60-byte tuple of Int8
- `ByteStorage1020`: 1020-byte tuple of Int8

### Critical Design Constraints

1. **POD Types Only:** Memory-mapped storage requires types to be trivially copyable with no object references. Validated at runtime with `_isPOD()` check.

2. **Tuple Storage:** Fixed-size arrays use tuples (not Array) to ensure POD compliance. This allows the struct to be directly memory-mapped.

3. **Power-of-2 Capacity:** KeyValueStore capacity (256) must be power of 2 to use fast bitwise AND for modulo: `index & (capacity - 1)` instead of `index % capacity`.

4. **Odd Hash2:** The second hash for double hashing must be odd (coprime with power-of-2 capacity) to ensure all slots are probed: `hash2 | 1`.

5. **Lock Placement:** Locks are in MemoryMap, not in the stored structs (can't be POD with locks).

6. **⚠️ NEVER MODIFY MEMORY-MAPPED STRUCTURES:** DO NOT add, remove, or reorder fields in structs that are stored in MemoryMap (e.g., `KeyValueStoreStorage`, `KeyValueEntry`, `KeyValueStoreEntries`, `_BasicType`, `ByteStorage*`). These changes break on-disk file format compatibility, making old files unreadable and new files incompatible with old code. All optimizations must preserve the exact memory layout. If you need to track additional state (like counts or metadata), store it in the wrapping class (e.g., `KeyValueStore`), NOT in the memory-mapped structures.

7. **⚠️ MINIMIZE DISK WRITES:** Every modification to POD structures results in an immediate disk write due to `MAP_SHARED` memory mapping. When updating entries:
   - **Prefer direct field modification** over copy-modify-write: `entries[i].value = newValue` instead of `var entry = entries[i]; entry.value = newValue; entries[i] = entry`
   - **Batch related changes** within the same `withUnsafeMutableBytes` closure
   - **Avoid unnecessary writes:** Don't write if the value hasn't changed
   - Each struct assignment triggers a disk write of the entire struct, so minimizing assignments reduces I/O overhead

## Development Commands

### Building and Testing
```bash
# Build
swift build

# Run all tests
swift test

# Run specific test (by name or with class prefix)
swift test --filter testPerformanceInsert
swift test --filter KeyValueStoreTests.testSetAndGet

# Run performance benchmarks only
swift test --filter testPerformance

# Run with sanitizers
swift test --sanitize thread
swift test --sanitize address
swift test --sanitize undefined
```

### Code Formatting
```bash
# Format code (required before commits)
swiftformat Sources/ Tests/

# Configuration in .swiftformat:
# - 4-space indent
# - 120 char max width
# - Swift 6.0
```

### Performance Testing
```bash
# Run all performance tests (shows average times)
swift test --filter testPerformance

# GitHub Actions runs benchmarks on PRs and posts results as comments
```

## Performance Characteristics

### Load Factor Performance (Capacity: 256 entries)
Lookup performance measured with 10,000+ lookups at various load factors:

- **25% load (64 keys):** ~11.4μs per lookup
- **50% load (128 keys):** ~11.6μs per lookup
- **75% load (192 keys):** ~11.6μs per lookup
- **90% load (230 keys):** ~11.6μs per lookup
- **99% load (253 keys):** ~12.1μs per lookup

**Key insights:**
- Performance remains remarkably consistent (~11-12μs) across all load factors
- Double hashing effectively prevents collision chains even at 99% capacity
- Recommended to keep ≤200 keys for ~78% load factor with optimal performance
- Capacity must be power of 2 for efficient modulo operations via bitwise AND

### Optimization Guidelines
- Operations use `@inline(__always)` on hot paths
- Lock overhead is negligible (~5-10ns, <0.03% of total operation time)
- All hot paths access raw storage buffer once using `withUnsafeBytes`/`withUnsafeMutableBytes`
- Hash collisions are minimized by double hashing with FNV-1a hash1 and guaranteed-odd hash2

### Optimization Notes
- **Eliminated subscript overhead:** All hot paths now access raw storage buffer once using `withUnsafeBytes`/`withUnsafeMutableBytes` instead of repeated subscript calls
- **Pattern:** Access `storage.entries.storage` once, bind to typed pointer, then iterate/probe using direct pointer indexing
- **Results:** Achieved consistent ~11-12μs per lookup across all load factors:
  - Count operation: ~7ms for 100 count operations
  - Keys enumeration: ~0.06ms for 100 keys
  - Insert/Update: ~1-2ms for 100 operations
  - Lookup: ~2-3ms for 100 operations
  - Contains: ~1.5ms for 100 operations

## Common Patterns

### Using Custom Locks
```swift
// Single-threaded (no locking overhead)
let memoryMap1 = try MemoryMap<MyData>(fileURL: url, lock: NoLock())

// Use NSLock
let memoryMap2 = try MemoryMap<MyData>(fileURL: url, lock: NSLock())

// Default: OSAllocatedUnfairLock
let memoryMap3 = try MemoryMap<MyData>(fileURL: url)

// Same options for KeyValueStore
let store = try KeyValueStore<BasicType64, MyValue>(fileURL: url, lock: NoLock())
```

### Adding New BasicType Sizes
1. Add new `ByteStorage` struct with appropriate tuple size in ByteStorage.swift
2. Add typealias: `public typealias BasicTypeN = _BasicType<ByteStorageN>`
3. Document size and use case

### Modifying KeyValueStore Capacity
1. Update `KeyValueStoreDefaultCapacity` constant
2. Must be power of 2
3. Update `KeyValueStoreEntries.storage` tuple to match
4. Update documentation and benchmarks

### Working with Memory-Mapped Files
- Use `withLockedStorage` for thread-safe batch operations
- Use `withUnsafeStorage` only when managing external locking
- Changes write immediately to disk (MAP_SHARED)
- No need to call `msync()` - OS handles flushing

## Code Style

### Naming Conventions
- **Types:** PascalCase (`KeyValueStore`, `BasicType64`, `MemoryMapError`)
- **Functions/Methods:** camelCase (`withLockedStorage`, `setValue`)
- **Variables/Properties:** camelCase (`memoryMap`, `fileURL`)
- **Private members:** Prefix with underscore (`_s`, `_hash1()`)
- **Generic parameters:** Single letter or descriptive (`T`, `Key`, `Value`, `Storage`)

### Documentation
- Use `///` for documentation comments on public APIs
- Include code examples in ```` ```swift ```` blocks for complex APIs
- Document parameters with `- Parameters:` and throws with `- Throws:`
- Mark sections with `// MARK: - Section Name`

### Error Handling
- Define errors as enums conforming to `Error`
- Subscript setters fail silently; use explicit methods (e.g., `setValue`) for error handling

### Imports
```swift
import Foundation
import os
```

## Testing Notes

- Performance tests use `measure { }` blocks, report average time
- Tests create temporary files in system temp directory
- KeyValueStore tests verify both correctness and performance characteristics
- Load factor tests ensure consistent performance from 25% to 99% capacity
- Test classes end with `Tests` (`KeyValueStoreTests`)
- Test methods start with `test` (`testSetAndGet`)
- Performance tests start with `testPerformance` (`testPerformanceInsert`)
