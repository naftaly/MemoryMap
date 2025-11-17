@testable import MemoryMap
import XCTest

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
final class MixedOperationsProfile: XCTestCase {
    // MARK: - Baseline: Homogeneous Operations

    func testBenchmarkHomogeneousIntOnly() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        measure {
            for i in 0 ..< 200 {
                store[BasicType64("key\(i)")] = BasicType1024(i)
            }
        }
    }

    // MARK: - Mixed Type Operations (200 total)

    func testBenchmarkMixed200Operations() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        measure {
            for i in 0 ..< 50 {
                store[BasicType64("int\(i)")] = BasicType1024(i)
                store[BasicType64("str\(i)")] = BasicType1024("Value \(i)")
                store[BasicType64("bool\(i)")] = BasicType1024(i % 2 == 0)
                store[BasicType64("double\(i)")] = BasicType1024(Double(i) * 3.14)
            }
        }
    }

    // MARK: - Isolate Key Creation

    func testBenchmarkKeyCreationOnly() {
        measure {
            var keys: [BasicType64] = []
            keys.reserveCapacity(200)
            for i in 0 ..< 50 {
                keys.append(BasicType64("int\(i)"))
                keys.append(BasicType64("str\(i)"))
                keys.append(BasicType64("bool\(i)"))
                keys.append(BasicType64("double\(i)"))
            }
        }
    }

    // MARK: - Isolate Value Creation

    func testBenchmarkValueCreationMixed() {
        measure {
            var values: [BasicType1024] = []
            values.reserveCapacity(200)
            for i in 0 ..< 50 {
                values.append(BasicType1024(i))
                values.append(BasicType1024("Value \(i)"))
                values.append(BasicType1024(i % 2 == 0))
                values.append(BasicType1024(Double(i) * 3.14))
            }
        }
    }

    func testBenchmarkValueCreationHomogeneous() {
        measure {
            var values: [BasicType1024] = []
            values.reserveCapacity(200)
            for i in 0 ..< 200 {
                values.append(BasicType1024(i))
            }
        }
    }

    // MARK: - Isolate Store Insert

    func testBenchmarkStoreInsertPrebuilt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        // Prebuild keys and values
        var keys: [BasicType64] = []
        var values: [BasicType1024] = []
        for i in 0 ..< 50 {
            keys.append(BasicType64("int\(i)"))
            values.append(BasicType1024(i))
            keys.append(BasicType64("str\(i)"))
            values.append(BasicType1024("Value \(i)"))
            keys.append(BasicType64("bool\(i)"))
            values.append(BasicType1024(i % 2 == 0))
            keys.append(BasicType64("double\(i)"))
            values.append(BasicType1024(Double(i) * 3.14))
        }

        measure {
            for i in 0 ..< 200 {
                store[keys[i]] = values[i]
            }
        }
    }

    // MARK: - Test Hash Distribution

    func testMixedTypeHashDistribution() {
        var hashCounts: [Int: Int] = [:]

        for i in 0 ..< 50 {
            let int = BasicType1024(i).hashValue & 127
            let str = BasicType1024("Value \(i)").hashValue & 127
            let bool = BasicType1024(i % 2 == 0).hashValue & 127
            let double = BasicType1024(Double(i) * 3.14).hashValue & 127

            hashCounts[int, default: 0] += 1
            hashCounts[str, default: 0] += 1
            hashCounts[bool, default: 0] += 1
            hashCounts[double, default: 0] += 1
        }

        let maxCollisions = hashCounts.values.max() ?? 0
        let avgCollisions = Double(hashCounts.values.reduce(0, +)) / Double(hashCounts.count)

        print("\nHash distribution (128 buckets, 200 values):")
        print("  Unique buckets used: \(hashCounts.count)")
        print("  Max collisions in one bucket: \(maxCollisions)")
        print("  Average per bucket: \(String(format: "%.2f", avgCollisions))")
        print("  Ideal (uniform): \(String(format: "%.2f", 200.0 / 128.0))")
    }
}
