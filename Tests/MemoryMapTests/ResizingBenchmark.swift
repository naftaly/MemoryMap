@testable import MemoryMap
import XCTest

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
final class ResizingBenchmark: XCTestCase {
    // MARK: - Hash Table Resizing Investigation

    func testBenchmark200InsertsNoPrealloc() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        measure {
            for i in 0 ..< 200 {
                store[BasicType64("key\(i)")] = BasicType1024(i)
            }
        }
    }

    func testBenchmark100InsertThen100Lookup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        measure {
            // Insert phase
            for i in 0 ..< 100 {
                store[BasicType64("key\(i)")] = BasicType1024(i)
            }
            // Lookup phase
            for i in 0 ..< 100 {
                let _ = store[BasicType64("key\(i)")]
            }
        }
    }

    func testBenchmark200Lookups() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 200 {
            store[BasicType64("key\(i)")] = BasicType1024(i)
        }

        measure {
            for i in 0 ..< 200 {
                let _ = store[BasicType64("key\(i)")]
            }
        }
    }

    func testBenchmarkInterleavedInsertLookup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        measure {
            for i in 0 ..< 100 {
                store[BasicType64("key\(i)")] = BasicType1024(i)
                let _ = store[BasicType64("key\(i)")]
            }
        }
    }
}
