@testable import MemoryMap
import XCTest

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
final class BasicType1024Benchmarks: XCTestCase {
    // MARK: - Integer Benchmarks

    func testBenchmarkIntStorage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(i)
            }
        }
    }

    func testBenchmarkIntExtraction() {
        let values = (0 ..< 10000).map { BasicType1024($0) }
        measure {
            for value in values {
                let _ = value.intValue
            }
        }
    }

    func testBenchmarkInt64Storage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(Int64(i))
            }
        }
    }

    func testBenchmarkInt64Extraction() {
        let values = (0 ..< 10000).map { BasicType1024(Int64($0)) }
        measure {
            for value in values {
                let _ = value.int64Value
            }
        }
    }

    // MARK: - Floating Point Benchmarks

    func testBenchmarkDoubleStorage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(Double(i) * 3.14159)
            }
        }
    }

    func testBenchmarkDoubleExtraction() {
        let values = (0 ..< 10000).map { BasicType1024(Double($0) * 3.14159) }
        measure {
            for value in values {
                let _ = value.doubleValue
            }
        }
    }

    func testBenchmarkFloatStorage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(Float(i) * 3.14)
            }
        }
    }

    func testBenchmarkFloatExtraction() {
        let values = (0 ..< 10000).map { BasicType1024(Float($0) * 3.14) }
        measure {
            for value in values {
                let _ = value.floatValue
            }
        }
    }

    // MARK: - Boolean Benchmarks

    func testBenchmarkBoolStorage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(i % 2 == 0)
            }
        }
    }

    func testBenchmarkBoolExtraction() {
        let values = (0 ..< 10000).map { BasicType1024($0 % 2 == 0) }
        measure {
            for value in values {
                let _ = value.boolValue
            }
        }
    }

    // MARK: - String Benchmarks

    func testBenchmarkShortStringStorage() {
        let testString = "Hello"
        measure {
            for _ in 0 ..< 10000 {
                let _ = BasicType1024(testString)
            }
        }
    }

    func testBenchmarkShortStringExtraction() {
        let testString = "Hello"
        let values = (0 ..< 10000).map { _ in BasicType1024(testString) }
        measure {
            for value in values {
                let _ = value.stringValue
            }
        }
    }

    func testBenchmarkMediumStringStorage() {
        let testString = String(repeating: "Test ", count: 50) // ~250 chars
        measure {
            for _ in 0 ..< 1000 {
                let _ = BasicType1024(testString)
            }
        }
    }

    func testBenchmarkMediumStringExtraction() {
        let testString = String(repeating: "Test ", count: 50)
        let values = (0 ..< 1000).map { _ in BasicType1024(testString) }
        measure {
            for value in values {
                let _ = value.stringValue
            }
        }
    }

    func testBenchmarkLongStringStorage() {
        let testString = String(repeating: "A", count: 1000) // ~1KB
        measure {
            for _ in 0 ..< 1000 {
                let _ = BasicType1024(testString)
            }
        }
    }

    func testBenchmarkLongStringExtraction() {
        let testString = String(repeating: "A", count: 1000)
        let values = (0 ..< 1000).map { _ in BasicType1024(testString) }
        measure {
            for value in values {
                let _ = value.stringValue
            }
        }
    }

    func testBenchmarkUnicodeStringStorage() {
        let testString = "Hello 👋 World 🌍 Testing 🧪 " + String(repeating: "日本語", count: 10)
        measure {
            for _ in 0 ..< 1000 {
                let _ = BasicType1024(testString)
            }
        }
    }

    func testBenchmarkUnicodeStringExtraction() {
        let testString = "Hello 👋 World 🌍 Testing 🧪 " + String(repeating: "日本語", count: 10)
        let values = (0 ..< 1000).map { _ in BasicType1024(testString) }
        measure {
            for value in values {
                let _ = value.stringValue
            }
        }
    }

    // MARK: - KeyValueStore Integration Benchmarks

    func testBenchmarkKeyValueStoreIntOperations() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        measure {
            for i in 0 ..< 100 {
                store[BasicType64("key\(i)")] = BasicType1024(i)
            }
            for i in 0 ..< 100 {
                let _ = store[BasicType64("key\(i)")]?.intValue
            }
        }
    }

    func testBenchmarkKeyValueStoreStringOperations() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)
        let testString = "Test String Value"

        measure {
            for i in 0 ..< 100 {
                store[BasicType64("str\(i)")] = BasicType1024(testString)
            }
            for i in 0 ..< 100 {
                let _ = store[BasicType64("str\(i)")]?.stringValue
            }
        }
    }

    func testBenchmarkKeyValueStoreMixedOperations() throws {
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

    // MARK: - Memory Efficiency Benchmarks

    func testBenchmarkMemoryEfficiency() {
        // Create many BasicType1024 instances and measure memory usage
        let iterations = 10000
        measure {
            var values: [BasicType1024] = []
            values.reserveCapacity(iterations)
            for i in 0 ..< iterations {
                values.append(BasicType1024(i))
            }
            // Force retention
            XCTAssertEqual(values.count, iterations)
        }
    }

    func testBenchmarkStringMemoryEfficiency() {
        let testString = String(repeating: "Test", count: 100)
        measure {
            var values: [BasicType1024] = []
            values.reserveCapacity(1000)
            for _ in 0 ..< 1000 {
                values.append(BasicType1024(testString))
            }
            XCTAssertEqual(values.count, 1000)
        }
    }

    // MARK: - Round-Trip Benchmarks

    func testBenchmarkCompleteRoundTripInt() {
        measure {
            for i in 0 ..< 10000 {
                let stored = BasicType1024(i)
                let _ = stored.intValue
            }
        }
    }

    func testBenchmarkCompleteRoundTripString() {
        let testString = "Hello, World!"
        measure {
            for _ in 0 ..< 10000 {
                let stored = BasicType1024(testString)
                let _ = stored.stringValue
            }
        }
    }

    // MARK: - Equality Comparison Benchmarks

    func testBenchmarkEqualityInt() {
        let values = (0 ..< 1000).map { BasicType1024($0) }
        measure {
            var result = true
            for i in 0 ..< 1000 {
                result = result && (values[i] == values[i])
            }
            XCTAssertTrue(result)
        }
    }

    func testBenchmarkEqualityString() {
        let testString = "Test String Value"
        let values = (0 ..< 1000).map { _ in BasicType1024(testString) }
        measure {
            var result = true
            for i in 0 ..< 1000 {
                result = result && (values[i] == values[i])
            }
            XCTAssertTrue(result)
        }
    }

    func testBenchmarkEqualityLongString() {
        let testString = String(repeating: "A", count: 500)
        let values = (0 ..< 1000).map { _ in BasicType1024(testString) }
        measure {
            var result = true
            for i in 0 ..< 1000 {
                result = result && (values[i] == values[i])
            }
            XCTAssertTrue(result)
        }
    }

    func testBenchmarkInequalityDifferentKind() {
        let intValues = (0 ..< 1000).map { BasicType1024($0) }
        let stringValues = (0 ..< 1000).map { BasicType1024("value\($0)") }
        measure {
            var result = true
            for i in 0 ..< 1000 {
                result = result && (intValues[i] != stringValues[i])
            }
            XCTAssertTrue(result)
        }
    }

    // MARK: - Hashing Benchmarks

    func testBenchmarkHashInt() {
        let values = (0 ..< 10000).map { BasicType1024($0) }
        measure {
            var hash = 0
            for value in values {
                hash ^= value.hashValue
            }
            XCTAssertNotEqual(hash, 0)
        }
    }

    func testBenchmarkHashString() {
        let values = (0 ..< 10000).map { BasicType1024("value\($0)") }
        measure {
            var hash = 0
            for value in values {
                hash ^= value.hashValue
            }
            XCTAssertNotEqual(hash, 0)
        }
    }

    func testBenchmarkDoubleHashInt() {
        let values = (0 ..< 10000).map { BasicType1024($0) }
        measure {
            var hash1 = 0
            var hash2 = 0
            for value in values {
                let hashes = value.hashes()
                hash1 ^= hashes.0
                hash2 ^= hashes.1
            }
            XCTAssertNotEqual(hash1, 0)
            XCTAssertNotEqual(hash2, 0)
        }
    }

    func testBenchmarkDoubleHashString() {
        let values = (0 ..< 10000).map { BasicType1024("str\($0)") }
        measure {
            var hash1 = 0
            var hash2 = 0
            for value in values {
                let hashes = value.hashes()
                hash1 ^= hashes.0
                hash2 ^= hashes.1
            }
            XCTAssertNotEqual(hash1, 0)
            XCTAssertNotEqual(hash2, 0)
        }
    }

    // MARK: - Unsigned Integer Benchmarks

    func testBenchmarkUIntStorage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(UInt(i))
            }
        }
    }

    func testBenchmarkUIntExtraction() {
        let values = (0 ..< 10000).map { BasicType1024(UInt($0)) }
        measure {
            for value in values {
                let _ = value.uintValue
            }
        }
    }

    func testBenchmarkUInt8Storage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(UInt8(i % 256))
            }
        }
    }

    func testBenchmarkUInt8Extraction() {
        let values = (0 ..< 10000).map { BasicType1024(UInt8($0 % 256)) }
        measure {
            for value in values {
                let _ = value.uint8Value
            }
        }
    }

    // MARK: - Type Discrimination Benchmarks

    func testBenchmarkTypeChecking() {
        let values: [BasicType1024] = (0 ..< 1000).flatMap { i in
            [
                BasicType1024(i),
                BasicType1024(Double(i)),
                BasicType1024("value\(i)"),
                BasicType1024(i % 2 == 0),
            ]
        }
        measure {
            var intCount = 0
            var doubleCount = 0
            var stringCount = 0
            var boolCount = 0
            for value in values {
                switch value.kind {
                case .int: intCount += 1
                case .double: doubleCount += 1
                case .string: stringCount += 1
                case .bool: boolCount += 1
                default: break
                }
            }
            XCTAssertEqual(intCount + doubleCount + stringCount + boolCount, 4000)
        }
    }

    func testBenchmarkWrongTypeExtraction() {
        let values = (0 ..< 10000).map { BasicType1024($0) }
        measure {
            for value in values {
                // Try to extract as wrong types - all should return nil
                let _ = value.stringValue
                let _ = value.doubleValue
                let _ = value.boolValue
            }
        }
    }

    // MARK: - Small Integer Type Benchmarks

    func testBenchmarkInt8Storage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(Int8(i % 128))
            }
        }
    }

    func testBenchmarkInt16Storage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(Int16(i))
            }
        }
    }

    func testBenchmarkInt32Storage() {
        measure {
            for i in 0 ..< 10000 {
                let _ = BasicType1024(Int32(i))
            }
        }
    }

    // MARK: - Direct Construction vs Literal Benchmarks

    func testBenchmarkIntLiteralConstruction() {
        measure {
            var values: [BasicType1024] = []
            values.reserveCapacity(10000)
            for i in 0 ..< 10000 {
                values.append(BasicType1024(integerLiteral: i))
            }
        }
    }

    func testBenchmarkStringLiteralInline() {
        // Test if literal construction has different performance
        measure {
            var values: [BasicType1024] = []
            values.reserveCapacity(100)
            for _ in 0 ..< 100 {
                values.append("test")
            }
        }
    }

    // MARK: - Comparison with Swift Native Types

    func testBenchmarkBaselineIntArray() {
        // Baseline: just creating Int values in an array
        measure {
            var values: [Int] = []
            values.reserveCapacity(10000)
            for i in 0 ..< 10000 {
                values.append(i)
            }
        }
    }

    func testBenchmarkBaselineStringArray() {
        // Baseline: just creating String values in an array
        let testString = "Hello"
        measure {
            var values: [String] = []
            values.reserveCapacity(10000)
            for _ in 0 ..< 10000 {
                values.append(testString)
            }
        }
    }

    func testBenchmarkBasicTypeIntArray() {
        // Compare: creating BasicType values in an array
        measure {
            var values: [BasicType1024] = []
            values.reserveCapacity(10000)
            for i in 0 ..< 10000 {
                values.append(BasicType1024(i))
            }
        }
    }

    func testBenchmarkBasicTypeStringArray() {
        // Compare: creating BasicType values in an array
        let testString = "Hello"
        measure {
            var values: [BasicType1024] = []
            values.reserveCapacity(10000)
            for _ in 0 ..< 10000 {
                values.append(BasicType1024(testString))
            }
        }
    }
}
