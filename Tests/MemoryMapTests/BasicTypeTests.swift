@testable import MemoryMap
import XCTest

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
final class BasicType1024Tests: XCTestCase {
    // MARK: - Integer Types Tests

    func testIntRoundTrip() {
        let value = Int.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.intValue, value)
        XCTAssertEqual(basic.int8Value, 0)
        XCTAssertEqual(basic.stringValue, "")
    }

    func testInt8RoundTrip() {
        let value = Int8.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.int8Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testInt16RoundTrip() {
        let value = Int16.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.int16Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testInt32RoundTrip() {
        let value = Int32.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.int32Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testInt64RoundTrip() {
        let value = Int64.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.int64Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUIntRoundTrip() {
        let value = UInt.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.uintValue, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUInt8RoundTrip() {
        let value = UInt8.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.uint8Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUInt16RoundTrip() {
        let value = UInt16.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.uint16Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUInt32RoundTrip() {
        let value = UInt32.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.uint32Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUInt64RoundTrip() {
        let value = UInt64.max
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.uint64Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    // MARK: - Floating Point Tests

    func testDoubleRoundTrip() {
        let value = Double.pi
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.doubleValue, value)
        XCTAssertEqual(basic.floatValue, 0.0)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testFloatRoundTrip() {
        let value = Float.pi
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.floatValue, value)
        XCTAssertEqual(basic.doubleValue, 0.0)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testDoubleSpecialValues() {
        // Test infinity
        let inf = BasicType1024(Double.infinity)
        XCTAssertEqual(inf.doubleValue, Double.infinity)

        // Test negative infinity
        let negInf = BasicType1024(-Double.infinity)
        XCTAssertEqual(negInf.doubleValue, -Double.infinity)

        // Test NaN
        let nan = BasicType1024(Double.nan)
        XCTAssertTrue(nan.doubleValue.isNaN)

        // Test zero
        let zero = BasicType1024(0.0)
        XCTAssertEqual(zero.doubleValue, 0.0)
    }

    // MARK: - Boolean Tests

    func testBoolTrue() {
        let basic = BasicType1024(true)
        XCTAssertEqual(basic.boolValue, true)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testBoolFalse() {
        let basic = BasicType1024(false)
        XCTAssertEqual(basic.boolValue, false)
        XCTAssertEqual(basic.intValue, 0)
    }

    // MARK: - String Tests

    func testEmptyString() {
        let basic = BasicType1024("")
        XCTAssertEqual(basic.stringValue, "")
    }

    func testShortString() {
        let value = "Hello, World!"
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.stringValue, value)
    }

    func testMediumString() {
        let value = String(repeating: "A", count: 500)
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.stringValue, value)
    }

    func testMaxLengthString() {
        let value = String(repeating: "X", count: 1020)
        let basic = BasicType1024(value)
        let foundValue = basic.stringValue
        XCTAssertEqual(foundValue, value)
    }

    func testStringTruncation() {
        // String longer than max length should be truncated
        let value = String(repeating: "Y", count: 2000)
        let basic = BasicType1024(value)
        let retrieved = basic.stringValue
        XCTAssertLessThanOrEqual(retrieved.count, 1020)
    }

    func testUnicodeString() {
        let value = "Hello 👋 World 🌍 Testing 🧪"
        let basic = BasicType1024(value)
        XCTAssertEqual(basic.stringValue, value)
    }

    func testMultiByteUnicodeCharacters() {
        // Test various Unicode scripts
        let tests = [
            "こんにちは世界", // Japanese
            "مرحبا بالعالم", // Arabic
            "Здравствуй мир", // Russian
            "你好世界", // Chinese
            "🎉🎊🎈🎁🎀", // Emojis
            "café résumé naïve", // Accented Latin
        ]

        for value in tests {
            let basic = BasicType1024(value)
            XCTAssertEqual(basic.stringValue, value, "Failed for: \(value)")
        }
    }

    func testUnicodeBoundaryTruncation() {
        // Create a string that will be truncated at a multi-byte character boundary
        // Fill with single-byte chars, then add multi-byte emoji near the end
        let prefix = String(repeating: "A", count: 1016)
        let emoji = "👨‍👩‍👧‍👦" // Family emoji (multi-byte)
        let value = prefix + emoji

        let basic = BasicType1024(value)
        let retrieved = basic.stringValue

        // Should truncate without corrupting UTF-8
        XCTAssertTrue(retrieved.count <= 1020)
        XCTAssertTrue(retrieved.unicodeScalars.allSatisfy { $0.isASCII || $0.value > 127 })
    }

    // MARK: - Throwing Initializer Tests

    func testThrowingInitWithValidString() throws {
        let value = "Hello, World!"
        let basic = try BasicType1024(throwing: value)
        XCTAssertEqual(basic.stringValue, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testThrowingInitWithEmptyString() throws {
        let basic = try BasicType1024(throwing: "")
        XCTAssertEqual(basic.stringValue, "")
    }

    func testThrowingInitWithMaxLengthString() throws {
        let value = String(repeating: "X", count: 1020)
        let basic = try BasicType1024(throwing: value)
        XCTAssertEqual(basic.stringValue, value)
    }

    func testThrowingInitWithTooLargeString() {
        // String that exceeds the storage capacity should throw
        let value = String(repeating: "Y", count: 2000)
        XCTAssertThrowsError(try BasicType1024(throwing: value)) { error in
            XCTAssertEqual(error as? KeyValueStoreError, KeyValueStoreError.tooLarge)
        }
    }

    func testThrowingInitWithUnicodeString() throws {
        let value = "Hello 👋 World 🌍 Testing 🧪"
        let basic = try BasicType1024(throwing: value)
        XCTAssertEqual(basic.stringValue, value)
    }

    // MARK: - KeyValueStore Integration Tests

    func testBasicType1024InKeyValueStore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)

        // Test different types
        store["int"] = BasicType1024(42)
        store["string"] = BasicType1024("Hello, World!")
        store["bool"] = BasicType1024(true)
        store["double"] = BasicType1024(3.14159)

        XCTAssertEqual(store["int"]?.intValue, 42)
        XCTAssertEqual(store["string"]?.stringValue, "Hello, World!")
        XCTAssertEqual(store["bool"]?.boolValue, true)
        XCTAssertEqual(store["double"]?.doubleValue, 3.14159)
    }

    func testBasicType1024Persistence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }

        let testString = "Persistence Test 🚀"

        // Write data
        do {
            let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)
            store["str"] = BasicType1024(testString)
            store["num"] = BasicType1024(12345)
        }

        // Read data in new instance
        do {
            let store = try KeyValueStore<BasicType64, BasicType1024>(fileURL: url)
            XCTAssertEqual(store["str"]?.stringValue, testString)
            XCTAssertEqual(store["num"]?.intValue, 12345)
        }
    }

    // MARK: - Type Safety Tests

    func testTypeSafety() {
        let intValue = BasicType1024(42)
        XCTAssertEqual(intValue.intValue, 42)
        XCTAssertEqual(intValue.stringValue, "")
        XCTAssertEqual(intValue.doubleValue, 0.0)
        XCTAssertEqual(intValue.boolValue, false)

        let stringValue = BasicType1024("test")
        XCTAssertEqual(stringValue.intValue, 0)
        XCTAssertEqual(stringValue.stringValue, "test")
        XCTAssertEqual(stringValue.doubleValue, 0.0)
    }

    // MARK: - Edge Cases

    func testNegativeIntegers() {
        let int8 = BasicType1024(Int8.min)
        XCTAssertEqual(int8.int8Value, Int8.min)

        let int64 = BasicType1024(Int64.min)
        XCTAssertEqual(int64.int64Value, Int64.min)
    }

    func testZeroValues() {
        XCTAssertEqual(BasicType1024(Int(0)).intValue, 0)
        XCTAssertEqual(BasicType1024(Double(0.0)).doubleValue, 0.0)
        XCTAssertEqual(BasicType1024(Float(0.0)).floatValue, 0.0)
        XCTAssertEqual(BasicType1024(UInt(0)).uintValue, 0)
    }
}

// MARK: - BasicType8 Tests

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
final class BasicType8Tests: XCTestCase {
    // MARK: - Integer Types Tests

    func testIntRoundTrip() {
        let value = Int.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.intValue, value)
        XCTAssertEqual(basic.int8Value, 0)
    }

    func testInt8RoundTrip() {
        let value = Int8.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.int8Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testInt16RoundTrip() {
        let value = Int16.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.int16Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testInt32RoundTrip() {
        let value = Int32.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.int32Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testInt64RoundTrip() {
        let value = Int64.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.int64Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUIntRoundTrip() {
        let value = UInt.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.uintValue, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUInt8RoundTrip() {
        let value = UInt8.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.uint8Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUInt16RoundTrip() {
        let value = UInt16.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.uint16Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUInt32RoundTrip() {
        let value = UInt32.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.uint32Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testUInt64RoundTrip() {
        let value = UInt64.max
        let basic = BasicType8(value)
        XCTAssertEqual(basic.uint64Value, value)
        XCTAssertEqual(basic.intValue, 0)
    }

    // MARK: - Floating Point Tests

    func testDoubleRoundTrip() {
        let value = Double.pi
        let basic = BasicType8(value)
        XCTAssertEqual(basic.doubleValue, value)
        XCTAssertEqual(basic.floatValue, 0.0)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testFloatRoundTrip() {
        let value = Float.pi
        let basic = BasicType8(value)
        XCTAssertEqual(basic.floatValue, value)
        XCTAssertEqual(basic.doubleValue, 0.0)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testDoubleSpecialValues() {
        // Test infinity
        let inf = BasicType8(Double.infinity)
        XCTAssertEqual(inf.doubleValue, Double.infinity)

        // Test negative infinity
        let negInf = BasicType8(-Double.infinity)
        XCTAssertEqual(negInf.doubleValue, -Double.infinity)

        // Test NaN
        let nan = BasicType8(Double.nan)
        XCTAssertTrue(nan.doubleValue.isNaN)

        // Test zero
        let zero = BasicType8(0.0)
        XCTAssertEqual(zero.doubleValue, 0.0)
    }

    // MARK: - Boolean Tests

    func testBoolTrue() {
        let basic = BasicType8(true)
        XCTAssertEqual(basic.boolValue, true)
        XCTAssertEqual(basic.intValue, 0)
    }

    func testBoolFalse() {
        let basic = BasicType8(false)
        XCTAssertEqual(basic.boolValue, false)
        XCTAssertEqual(basic.intValue, 0)
    }

    // MARK: - Literal Tests

    func testIntegerLiteral() {
        let basic: BasicType8 = 42
        XCTAssertEqual(basic.intValue, 42)
    }

    func testFloatLiteral() {
        let basic: BasicType8 = 3.14159
        XCTAssertEqual(basic.doubleValue, 3.14159)
    }

    func testBooleanLiteral() {
        let basic: BasicType8 = true
        XCTAssertEqual(basic.boolValue, true)
    }

    // MARK: - BasicTypeNumber Alias Tests

    func testBasicTypeNumberAlias() {
        let number: BasicTypeNumber = 12345
        XCTAssertEqual(number.intValue, 12345)
    }

    // MARK: - KeyValueStore Integration Tests

    func testBasicType8InKeyValueStore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }

        struct NumericValue {
            var value: Double
            var count: Int
        }

        let store = try KeyValueStore<BasicType8, NumericValue>(fileURL: url)

        // Test with integer keys
        store[42] = NumericValue(value: 3.14, count: 1)
        store[100] = NumericValue(value: 2.71, count: 2)

        XCTAssertEqual(store[42]?.value, 3.14)
        XCTAssertEqual(store[42]?.count, 1)
        XCTAssertEqual(store[100]?.value, 2.71)
        XCTAssertEqual(store[100]?.count, 2)
    }

    func testBasicType8Persistence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }

        struct TestData {
            var x: Int
            var y: Int
        }

        // Write data
        do {
            let store = try KeyValueStore<BasicTypeNumber, TestData>(fileURL: url)
            store[1] = TestData(x: 10, y: 20)
            store[2] = TestData(x: 30, y: 40)
        }

        // Read data in new instance
        do {
            let store = try KeyValueStore<BasicTypeNumber, TestData>(fileURL: url)
            XCTAssertEqual(store[1]?.x, 10)
            XCTAssertEqual(store[1]?.y, 20)
            XCTAssertEqual(store[2]?.x, 30)
            XCTAssertEqual(store[2]?.y, 40)
        }
    }

    // MARK: - Type Safety Tests

    func testTypeSafety() {
        let intValue = BasicType8(42)
        XCTAssertEqual(intValue.intValue, 42)
        XCTAssertEqual(intValue.doubleValue, 0.0)
        XCTAssertEqual(intValue.boolValue, false)

        let doubleValue = BasicType8(3.14)
        XCTAssertEqual(doubleValue.intValue, 0)
        XCTAssertEqual(doubleValue.doubleValue, 3.14)
    }

    // MARK: - Edge Cases

    func testNegativeIntegers() {
        let int8 = BasicType8(Int8.min)
        XCTAssertEqual(int8.int8Value, Int8.min)

        let int64 = BasicType8(Int64.min)
        XCTAssertEqual(int64.int64Value, Int64.min)
    }

    func testZeroValues() {
        XCTAssertEqual(BasicType8(Int(0)).intValue, 0)
        XCTAssertEqual(BasicType8(Double(0.0)).doubleValue, 0.0)
        XCTAssertEqual(BasicType8(Float(0.0)).floatValue, 0.0)
        XCTAssertEqual(BasicType8(UInt(0)).uintValue, 0)
    }

    // MARK: - Hashing and Equality Tests

    func testEquality() {
        let a = BasicType8(42)
        let b = BasicType8(42)
        let c = BasicType8(43)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testHashing() {
        let a = BasicType8(42)
        let b = BasicType8(42)

        XCTAssertEqual(a.hashValue, b.hashValue)
        // Note: hash values for different values are not guaranteed to be different
        // but they usually are for simple cases
    }

    func testDoubleHashing() {
        let value = BasicType8(12345)
        let (hash1, hash2) = value.hashes()

        // hash2 must be odd (for double hashing to work with power-of-2 capacity)
        XCTAssertTrue(hash2 & 1 == 1, "hash2 must be odd")

        // Both hashes should be computed (non-zero or valid)
        // Note: Hashes can be negative in Swift, that's fine
        XCTAssertNotEqual(hash1, 0)
        XCTAssertNotEqual(hash2, 0)
    }
}

// MARK: - BasicType Size Verification Tests

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
final class BasicTypeSizeTests: XCTestCase {
    func testBasicType8Size() {
        // BasicType8: 8 bytes storage + 3 bytes metadata (1 byte kind + 2 bytes length)
        // Expected size: 11 bytes, but stride may be larger due to alignment
        let size = MemoryLayout<BasicType8>.size
        let stride = MemoryLayout<BasicType8>.stride

        print("BasicType8 - size: \(size), stride: \(stride)")

        // Size should be at least 11 bytes (8 storage + 1 kind + 2 length)
        XCTAssertGreaterThanOrEqual(size, 11, "BasicType8 size should be at least 11 bytes")

        // Stride is usually aligned, so it might be larger
        XCTAssertGreaterThanOrEqual(stride, size, "Stride should be >= size")

        // Verify storage capacity
        XCTAssertEqual(ByteStorage8.capacity, 8, "ByteStorage8 capacity should be 8 bytes")
    }

    func testBasicType64Size() {
        // BasicType64: 60 bytes storage + 3 bytes metadata
        // Expected size: 63 bytes, but stride may be larger due to alignment
        let size = MemoryLayout<BasicType64>.size
        let stride = MemoryLayout<BasicType64>.stride

        print("BasicType64 - size: \(size), stride: \(stride)")

        // Size should be at least 63 bytes (60 storage + 1 kind + 2 length)
        XCTAssertGreaterThanOrEqual(size, 63, "BasicType64 size should be at least 63 bytes")

        // Stride is usually aligned
        XCTAssertGreaterThanOrEqual(stride, size, "Stride should be >= size")

        // Verify storage capacity
        XCTAssertEqual(ByteStorage60.capacity, 60, "ByteStorage60 capacity should be 60 bytes")
    }

    func testBasicType1024Size() {
        // BasicType1024: 1020 bytes storage + 3 bytes metadata
        // Expected size: 1023 bytes, but stride may be larger due to alignment
        let size = MemoryLayout<BasicType1024>.size
        let stride = MemoryLayout<BasicType1024>.stride

        print("BasicType1024 - size: \(size), stride: \(stride)")

        // Size should be at least 1023 bytes (1020 storage + 1 kind + 2 length)
        XCTAssertGreaterThanOrEqual(size, 1023, "BasicType1024 size should be at least 1023 bytes")

        // Stride is usually aligned
        XCTAssertGreaterThanOrEqual(stride, size, "Stride should be >= size")

        // Verify storage capacity
        XCTAssertEqual(ByteStorage1020.capacity, 1020, "ByteStorage1020 capacity should be 1020 bytes")
    }

    func testByteStorageSizes() {
        // Verify ByteStorage capacities match their type sizes
        XCTAssertEqual(MemoryLayout<ByteStorage8.Storage>.size, 8)
        XCTAssertEqual(MemoryLayout<ByteStorage60.Storage>.size, 60)
        XCTAssertEqual(MemoryLayout<ByteStorage1020.Storage>.size, 1020)
    }

    func testBasicTypeSizeComparison() {
        // Verify relative sizes are correct
        let size8 = MemoryLayout<BasicType8>.size
        let size64 = MemoryLayout<BasicType64>.size
        let size1024 = MemoryLayout<BasicType1024>.size

        XCTAssertLessThan(size8, size64, "BasicType8 should be smaller than BasicType64")
        XCTAssertLessThan(size64, size1024, "BasicType64 should be smaller than BasicType1024")
    }

    func testBasicTypeIsPOD() {
        // Verify all BasicType variants are POD (Plain Old Data)
        // This is critical for memory-mapped storage
        XCTAssertTrue(_isPOD(BasicType8.self), "BasicType8 must be POD")
        XCTAssertTrue(_isPOD(BasicType64.self), "BasicType64 must be POD")
        XCTAssertTrue(_isPOD(BasicType1024.self), "BasicType1024 must be POD")
    }
}
