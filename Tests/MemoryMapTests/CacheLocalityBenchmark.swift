@testable import MemoryMap
import XCTest

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
final class CacheLocalityBenchmark: XCTestCase {
    // MARK: - Cache Locality Hypothesis Testing

    func testBenchmark50InsertThen50Lookup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        measure {
            // 50 inserts (working set: ~50 entries = ~100KB < L2 cache)
            for i in 0 ..< 50 {
                store[BasicType64("key\(i)")] = BasicType1024(i)
            }
            // 50 lookups (same entries, should be L2 cache hits!)
            for i in 0 ..< 50 {
                let _ = store[BasicType64("key\(i)")]
            }
        }
    }

    func testBenchmark150InsertThen150Lookup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        measure {
            // 150 inserts (working set: ~128 entries due to hash table size = ~263KB > L2 cache)
            for i in 0 ..< 150 {
                store[BasicType64("key\(i)")] = BasicType1024(i)
            }
            // 150 lookups (entries may be evicted from L2, cache misses)
            for i in 0 ..< 150 {
                let _ = store[BasicType64("key\(i)")]
            }
        }
    }

    func testBenchmark100InsertWithoutLookup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        measure {
            // Just 100 inserts, no lookups (should be reasonably fast due to smaller working set)
            for i in 0 ..< 100 {
                store[BasicType64("key\(i)")] = BasicType1024(i)
            }
        }
    }

    func testBenchmark200InsertDifferentKeysEachTime() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        var iterationCounter = 0
        measure {
            // Use different keys each iteration to force real inserts, not updates
            let base = iterationCounter * 200
            for i in 0 ..< 200 {
                store[BasicType64("key\(base + i)")] = BasicType1024(i)
            }
            iterationCounter += 1
        }
    }
}
