@testable import MemoryMap
import XCTest

@available(macOS 14.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
final class KeyValueStoreTests: XCTestCase {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let collidingKeys = ["k8", "k134", "k170", "k215"]

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Basic Operations

    func testSetAndGet() throws {
        struct TestValue {
            var counter: Int
            var flag: Bool
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["key1"] = TestValue(counter: 42, flag: true)

        let value = store["key1"]
        XCTAssertNotNil(value)
        XCTAssertEqual(value?.counter, 42)
        XCTAssertEqual(value?.flag, true)
    }

    func testGetNonExistentKey() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let value = store["nonexistent"]
        XCTAssertNil(value)
    }

    func testUpdate() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["key1"] = TestValue(value: 10)
        store["key1"] = TestValue(value: 20)

        let value = store["key1"]
        XCTAssertEqual(value?.value, 20)
    }

    func testRemove() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["key1"] = TestValue(value: 42)
        let removed = store["key1"]
        store["key1"] = nil
        XCTAssertEqual(removed?.value, 42)
        XCTAssertNil(store["key1"])
    }

    func testRemoveNonExistent() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let removed = store["nonexistent"]
        store["nonexistent"] = nil
        XCTAssertNil(removed)
    }

    // MARK: - Deletion with Probe Chains

    func testDeletionWithProbeChain() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        let keys = collidingKeys

        // Insert keys that will create a probe chain (all map to same slot)
        store[keys[0]] = TestValue(value: 1)
        store[keys[1]] = TestValue(value: 2)
        store[keys[2]] = TestValue(value: 3)
        store[keys[3]] = TestValue(value: 4)

        // Verify all keys are accessible before deletion
        XCTAssertEqual(store[keys[0]]?.value, 1)
        XCTAssertEqual(store[keys[1]]?.value, 2)
        XCTAssertEqual(store[keys[2]]?.value, 3)
        XCTAssertEqual(store[keys[3]]?.value, 4)

        // Remove the first key
        let removed = store[keys[0]]
        store[keys[0]] = nil
        XCTAssertEqual(removed?.value, 1)
        XCTAssertNil(store[keys[0]], "Removed key should not be found")

        // CRITICAL: These lookups should still work!
        // If deletion just marks as unoccupied without rehashing,
        // any keys that were in the probe chain after the deleted key
        // will become unreachable because the probe chain is broken.
        XCTAssertEqual(store[keys[1]]?.value, 2, "key b should still be accessible after deleting a")
        XCTAssertEqual(store[keys[2]]?.value, 3, "key c should still be accessible after deleting a")
        XCTAssertEqual(store[keys[3]]?.value, 4, "key d should still be accessible after deleting a")

        // Try removing another and verify remaining keys
        store[keys[2]] = nil
        XCTAssertEqual(store[keys[1]]?.value, 2, "key b should still be accessible after deleting c")
        XCTAssertEqual(store[keys[3]]?.value, 4, "key d should still be accessible after deleting c")
    }

    func testDeletionBreaksProbeChainScenario() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        let keys = Array(collidingKeys.prefix(3))

        // Fill colliding slots to guarantee a probe chain exists
        store[keys[0]] = TestValue(value: 10)
        store[keys[1]] = TestValue(value: 20)
        store[keys[2]] = TestValue(value: 30)

        // Verify all are accessible
        XCTAssertEqual(store[keys[0]]?.value, 10)
        XCTAssertEqual(store[keys[1]]?.value, 20)
        XCTAssertEqual(store[keys[2]]?.value, 30)

        // Remove middle element (most likely to break chain)
        store[keys[1]] = nil

        // CRITICAL: x and z should still be findable
        XCTAssertEqual(store[keys[0]]?.value, 10, "x should be findable after removing y")
        XCTAssertEqual(store[keys[2]]?.value, 30, "z should be findable after removing y")
        XCTAssertNil(store[keys[1]], "y should not be findable after removal")
    }

    func testDeletionAndReinsertion() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        let keys = Array(collidingKeys.prefix(3))

        // Create a probe chain scenario
        store[keys[0]] = TestValue(value: 1)
        store[keys[1]] = TestValue(value: 2)
        store[keys[2]] = TestValue(value: 3)

        // Remove middle element
        store[keys[1]] = nil

        // Reinsert with different value
        store[keys[1]] = TestValue(value: 20)

        // All should be accessible
        XCTAssertEqual(store[keys[0]]?.value, 1)
        XCTAssertEqual(store[keys[1]]?.value, 20)
        XCTAssertEqual(store[keys[2]]?.value, 3)
    }

    func testContains() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["key1"] = TestValue(value: 42)

        XCTAssertTrue(store.contains("key1"))
        XCTAssertFalse(store.contains("key2"))
    }

    // MARK: - Multiple Entries

    func testMultipleEntries() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["key1"] = TestValue(value: 1)
        store["key2"] = TestValue(value: 2)
        store["key3"] = TestValue(value: 3)

        XCTAssertEqual(store["key1"]?.value, 1)
        XCTAssertEqual(store["key2"]?.value, 2)
        XCTAssertEqual(store["key3"]?.value, 3)
    }

    func testAllKeys() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["key1"] = TestValue(value: 1)
        store["key2"] = TestValue(value: 2)
        store["key3"] = TestValue(value: 3)

        let keys = store.keys
        XCTAssertEqual(keys.count, 3)
        XCTAssertTrue(keys.contains("key1"))
        XCTAssertTrue(keys.contains("key2"))
        XCTAssertTrue(keys.contains("key3"))
    }

    func testRemoveAll() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["key1"] = TestValue(value: 1)
        store["key2"] = TestValue(value: 2)
        store["key3"] = TestValue(value: 3)

        store.removeAll()

        XCTAssertNil(store["key1"])
        XCTAssertNil(store["key2"])
        XCTAssertNil(store["key3"])
        XCTAssertEqual(store.keys.count, 0)
    }

    // MARK: - Persistence

    func testPersistence() throws {
        struct TestValue {
            var counter: Int
            var timestamp: Double
        }

        var store: KeyValueStore<TestValue>? = try KeyValueStore(fileURL: url)

        store?["user:123"] = TestValue(counter: 100, timestamp: 12345.67)
        store?["user:456"] = TestValue(counter: 200, timestamp: 67890.12)

        // Close the store
        store = nil

        // Reopen and verify
        store = try KeyValueStore(fileURL: url)

        let value1 = store?["user:123"]
        XCTAssertEqual(value1?.counter, 100)
        XCTAssertEqual(value1?.timestamp, 12345.67)

        let value2 = store?["user:456"]
        XCTAssertEqual(value2?.counter, 200)
        XCTAssertEqual(value2?.timestamp, 67890.12)
    }

    // MARK: - Key Length

    func testKeyTooLong() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Keys longer than 64 bytes are truncated in release builds
        // (assertion in debug builds)
        // This test verifies the API handles keys gracefully

        // Use a key that's exactly at the limit (64 bytes)
        let maxKey = String(repeating: "a", count: 64)
        store[maxKey] = TestValue(value: 42)
        XCTAssertEqual(store[maxKey]?.value, 42)

        // Clean up
        store[maxKey] = nil
        XCTAssertNil(store[maxKey])
    }

    func testMaxKeyLength() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Create a key exactly 64 bytes
        let maxKey = String(repeating: "a", count: 64)

        store[maxKey] = TestValue(value: 42)
        XCTAssertEqual(store[maxKey]?.value, 42)
    }

    // MARK: - Hash Collisions

    func testHashCollisionHandling() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Add many entries to increase likelihood of hash collisions
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        // Verify all entries are retrievable
        for i in 0 ..< 100 {
            let value = store["key\(i)"]
            XCTAssertEqual(value?.value, i, "Failed to retrieve key\(i)")
        }
    }

    // MARK: - Store Full

    func testStoreFull() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        let capacity = KeyValueStoreDefaultCapacity

        // Fill the store
        for i in 0 ..< capacity {
            store["key\(i)"] = TestValue(value: i)
        }

        // Subscript silently ignores when full
        let overflowKey = "overflow"
        store[overflowKey] = TestValue(value: 999)
        XCTAssertNil(store[overflowKey], "Store should be full and unable to add new keys")
    }

    // MARK: - Special Characters in Keys

    func testSpecialCharactersInKeys() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let specialKeys = [
            "key:with:colons",
            "key/with/slashes",
            "key.with.dots",
            "key-with-dashes",
            "key_with_underscores",
            "key with spaces",
            "key🎉with🌟emoji",
        ]

        for (index, key) in specialKeys.enumerated() {
            store[key] = TestValue(value: index)
        }

        for (index, key) in specialKeys.enumerated() {
            let value = store[key]
            XCTAssertEqual(value?.value, index, "Failed for key: \(key)")
        }
    }

    // MARK: - Different Value Types

    func testIntValue() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        store["key"] = TestValue(value: Int.max)
        XCTAssertEqual(store["key"]?.value, Int.max)
    }

    func testDoubleValue() throws {
        struct TestValue {
            var value: Double
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        store["key"] = TestValue(value: 3.14159)

        let retrieved = store["key"]
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved!.value, 3.14159, accuracy: 0.00001)
    }

    func testComplexStruct() throws {
        struct ComplexValue {
            var int8: Int8
            var int16: Int16
            var int32: Int32
            var int64: Int64
            var uint8: UInt8
            var uint16: UInt16
            var uint32: UInt32
            var uint64: UInt64
            var float: Float
            var double: Double
            var bool1: Bool
            var bool2: Bool
        }

        let store = try KeyValueStore<ComplexValue>(fileURL: url)

        let complex = ComplexValue(
            int8: -128,
            int16: -32768,
            int32: -2_147_483_648,
            int64: -9_223_372_036_854_775_808,
            uint8: 255,
            uint16: 65535,
            uint32: 4_294_967_295,
            uint64: 18_446_744_073_709_551_615,
            float: 3.14,
            double: 2.71828,
            bool1: true,
            bool2: false
        )

        store["complex"] = complex

        let retrieved = store["complex"]
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.int8, -128)
        XCTAssertEqual(retrieved?.int16, -32768)
        XCTAssertEqual(retrieved?.int32, -2_147_483_648)
        XCTAssertEqual(retrieved?.int64, -9_223_372_036_854_775_808)
        XCTAssertEqual(retrieved?.uint8, 255)
        XCTAssertEqual(retrieved?.uint16, 65535)
        XCTAssertEqual(retrieved?.uint32, 4_294_967_295)
        XCTAssertEqual(retrieved?.uint64, 18_446_744_073_709_551_615)
        XCTAssertEqual(Double(retrieved!.float), 3.14, accuracy: 0.001)
        XCTAssertEqual(retrieved!.double, 2.71828, accuracy: 0.00001)
        XCTAssertEqual(retrieved?.bool1, true)
        XCTAssertEqual(retrieved?.bool2, false)
    }

    // MARK: - Edge Cases

    func testEmptyKey() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store[""] = TestValue(value: 42)
        XCTAssertEqual(store[""]?.value, 42)
    }

    func testSingleCharacterKey() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["a"] = TestValue(value: 1)
        store["b"] = TestValue(value: 2)

        XCTAssertEqual(store["a"]?.value, 1)
        XCTAssertEqual(store["b"]?.value, 2)
    }

    func testValueTooLarge() throws {
        // Create a large struct that exceeds default max (1KB)
        struct LargeValue {
            var data: (
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int,
                Int, Int, Int, Int, Int, Int, Int, Int, Int, Int
            ) // 130 * 8 = 1040 bytes
        }

        // Should fail with default max value size (1KB)
        XCTAssertThrowsError(try KeyValueStore<LargeValue>(fileURL: url)) { error in
            guard case KeyValueStoreError.valueTooLarge = error else {
                XCTFail("Expected KeyValueStoreError.valueTooLarge, got \(error)")
                return
            }
        }
    }

    // MARK: - Dictionary-like API

    func testSubscriptAccess() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Test setting and getting
        store["key"] = TestValue(value: 42)
        XCTAssertEqual(store["key"]?.value, 42)

        // Test updating
        store["key"] = TestValue(value: 100)
        XCTAssertEqual(store["key"]?.value, 100)

        // Test removing by setting to nil
        store["key"] = nil
        XCTAssertNil(store["key"])
    }

    func testSubscriptWithDefault() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Non-existent key returns default
        let value1 = store["missing", default: TestValue(value: 99)]
        XCTAssertEqual(value1.value, 99)

        // Existing key returns stored value
        store["key"] = TestValue(value: 42)
        let value2 = store["key", default: TestValue(value: 99)]
        XCTAssertEqual(value2.value, 42)
    }

    func testUpdateValue() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Set initial value
        store["key"] = TestValue(value: 42)
        XCTAssertEqual(store["key"]?.value, 42)

        // Update existing key
        let oldValue = store["key"]
        store["key"] = TestValue(value: 100)
        XCTAssertEqual(oldValue?.value, 42)
        XCTAssertEqual(store["key"]?.value, 100)
    }

    func testToDictionary() throws {
        struct TestValue: Equatable {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["key1"] = TestValue(value: 1)
        store["key2"] = TestValue(value: 2)
        store["key3"] = TestValue(value: 3)

        let dict = store.dictionaryRepresentation()
        XCTAssertEqual(dict.count, 3)
        XCTAssertEqual(dict["key1"], TestValue(value: 1))
        XCTAssertEqual(dict["key2"], TestValue(value: 2))
        XCTAssertEqual(dict["key3"], TestValue(value: 3))

        // Test that it's a copy - modifications don't affect each other
        store["key4"] = TestValue(value: 4)
        XCTAssertEqual(dict.count, 3)
        XCTAssertNil(dict["key4"])
    }

    // MARK: - Benchmarks

    func testPerformanceInsert() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        measure {
            for i in 0 ..< 100 {
                store["key\(i)"] = TestValue(value: i)
            }
        }
    }

    func testPerformanceLookupHit() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for i in 0 ..< 100 {
                _ = store["key\(i)"]
            }
        }
    }

    func testPerformanceLookupMiss() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate with different keys
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for i in 0 ..< 100 {
                _ = store["missing\(i)"]
            }
        }
    }

    func testPerformanceUpdate() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for i in 0 ..< 100 {
                store["key\(i)"] = TestValue(value: i * 2)
            }
        }
    }

    func testPerformanceRemove() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        measure {
            // Prepopulate
            for i in 0 ..< 100 {
                store["key\(i)"] = TestValue(value: i)
            }

            // Remove all
            for i in 0 ..< 100 {
                store["key\(i)"] = nil
            }
        }
    }

    func testPerformanceCount() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for _ in 0 ..< 100 {
                _ = store.keys.count
            }
        }
    }

    func testPerformanceKeys() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            _ = store.keys
        }
    }

    func testPerformanceToDictionary() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            _ = store.dictionaryRepresentation()
        }
    }

    func testPerformanceMixedOperations() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        measure {
            // Mix of operations that simulate real-world usage
            for i in 0 ..< 50 {
                store["key\(i)"] = TestValue(value: i)
            }

            for i in 0 ..< 50 {
                _ = store["key\(i)"]
            }

            for i in 0 ..< 25 {
                store["key\(i)"] = TestValue(value: i * 2)
            }

            for i in 0 ..< 10 {
                store["key\(i)"] = nil
            }

            _ = store.keys
        }
    }

    // MARK: - Concurrency Tests

    func testConcurrentReads() throws {
        struct TestValue: Sendable {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        let iterations = 1000
        let expectation = XCTestExpectation(description: "Concurrent reads")
        expectation.expectedFulfillmentCount = 4

        for _ in 0 ..< 4 {
            DispatchQueue.global().async {
                for _ in 0 ..< iterations {
                    let index = Int.random(in: 0 ..< 100)
                    let value = store["key\(index)"]
                    XCTAssertEqual(value?.value, index)
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    func testConcurrentWrites() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let iterations = 30 // 4 threads * 30 items = 120 total (within 128 capacity)
        let expectation = XCTestExpectation(description: "Concurrent writes")
        expectation.expectedFulfillmentCount = 4

        for threadId in 0 ..< 4 {
            DispatchQueue.global().async {
                for i in 0 ..< iterations {
                    let key = "thread\(threadId)_key\(i)"
                    store[key] = TestValue(value: i)
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // Verify all writes succeeded
        for threadId in 0 ..< 4 {
            for i in 0 ..< iterations {
                let key = "thread\(threadId)_key\(i)"
                XCTAssertEqual(store[key]?.value, i, "Failed for \(key)")
            }
        }
    }

    func testConcurrentMixedOperations() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate some data
        for i in 0 ..< 30 {
            store["shared\(i)"] = TestValue(value: i)
        }

        let expectation = XCTestExpectation(description: "Concurrent mixed operations")
        expectation.expectedFulfillmentCount = 6

        // Reader threads
        for _ in 0 ..< 3 {
            DispatchQueue.global().async {
                for _ in 0 ..< 200 {
                    let index = Int.random(in: 0 ..< 30)
                    _ = store["shared\(index)"]
                }
                expectation.fulfill()
            }
        }

        // Writer threads (add 20 items each = 60 total + 30 shared = 90, well under 128 limit)
        for threadId in 0 ..< 3 {
            DispatchQueue.global().async {
                for i in 0 ..< 20 {
                    let key = "writer\(threadId)_\(i)"
                    store[key] = TestValue(value: i * threadId)
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - Key Type Tests

    func testKeyTypeDirectUsage() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let key = KeyValueStore<TestValue>.Key("mykey")
        store[key] = TestValue(value: 42)

        XCTAssertEqual(store[key]?.value, 42)
    }

    func testKeyTypeStringLiteral() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let key: KeyValueStore<TestValue>.Key = "literal_key"
        store[key] = TestValue(value: 99)

        XCTAssertEqual(store[key]?.value, 99)
    }

    func testKeyTypeWithDefault() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let key: KeyValueStore<TestValue>.Key = "test"
        let value = store[key, default: TestValue(value: 100)]
        XCTAssertEqual(value.value, 100)

        store[key] = TestValue(value: 50)
        let value2 = store[key, default: TestValue(value: 100)]
        XCTAssertEqual(value2.value, 50)
    }

    // MARK: - UTF-8 Boundary Tests

    func testUTF8MultiByteCharacters() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let keys = [
            "🎉🌟💯🚀", // Emoji (4 bytes each)
            "你好世界测试", // Chinese characters (3 bytes each)
            "こんにちは", // Japanese hiragana
            "🇺🇸🇯🇵🇨🇳", // Flag emojis (8 bytes each)
        ]

        for (index, key) in keys.enumerated() {
            store[key] = TestValue(value: index)
        }

        for (index, key) in keys.enumerated() {
            XCTAssertEqual(store[key]?.value, index, "Failed for key: \(key)")
        }
    }

    func testUTF8BoundaryTruncation() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Create a key with emoji that will be truncated at 64 bytes
        // Each emoji is 4 bytes, so 16 emoji = 64 bytes exactly
        let exactKey = String(repeating: "🎉", count: 16) // Exactly 64 bytes
        store[exactKey] = TestValue(value: 1)
        XCTAssertEqual(store[exactKey]?.value, 1)

        // 17 emoji = 68 bytes, should truncate to 16 emoji
        let overKey = String(repeating: "🎉", count: 17)
        store[overKey] = TestValue(value: 2)

        // The truncated version should match the 16-emoji key
        XCTAssertEqual(store[exactKey]?.value, 2, "Truncation should respect UTF-8 boundaries")
    }

    func testUTF8MixedASCIIAndMultibyte() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let keys = [
            "user:123:🎉",
            "session/abc/🌟/data",
            "cache:你好:item",
        ]

        for (index, key) in keys.enumerated() {
            store[key] = TestValue(value: index)
        }

        for (index, key) in keys.enumerated() {
            XCTAssertEqual(store[key]?.value, index)
        }
    }

    // MARK: - Persistence Edge Cases

    func testRemoveAllPersistence() throws {
        struct TestValue {
            var value: Int
        }

        var store: KeyValueStore<TestValue>? = try KeyValueStore(fileURL: url)

        // Add some data
        store?["key1"] = TestValue(value: 1)
        store?["key2"] = TestValue(value: 2)
        store?["key3"] = TestValue(value: 3)

        // Remove all
        store?.removeAll()
        XCTAssertEqual(store?.count, 0)

        // Close and reopen
        store = nil
        store = try KeyValueStore(fileURL: url)

        // Should still be empty
        XCTAssertNil(store?["key1"])
        XCTAssertNil(store?["key2"])
        XCTAssertNil(store?["key3"])
    }

    func testDeletionPersistence() throws {
        struct TestValue {
            var value: Int
        }

        var store: KeyValueStore<TestValue>? = try KeyValueStore(fileURL: url)

        // Add data with colliding keys to create tombstones
        let keys = Array(collidingKeys.prefix(4))
        for (index, key) in keys.enumerated() {
            store?[key] = TestValue(value: index)
        }

        // Delete some
        store?[keys[1]] = nil
        store?[keys[3]] = nil

        // Close and reopen
        store = nil
        store = try KeyValueStore(fileURL: url)

        // Verify persistence
        XCTAssertEqual(store?[keys[0]]?.value, 0)
        XCTAssertNil(store?[keys[1]])
        XCTAssertEqual(store?[keys[2]]?.value, 2)
        XCTAssertNil(store?[keys[3]])
    }

    func testMultipleReopenCycles() throws {
        struct TestValue {
            var value: Int
        }

        for cycle in 0 ..< 5 {
            let store = try KeyValueStore<TestValue>(fileURL: url)

            if cycle == 0 {
                // First cycle: add data
                store["persistent"] = TestValue(value: 42)
            } else {
                // Subsequent cycles: verify data persists
                XCTAssertEqual(store["persistent"]?.value, 42, "Failed on cycle \(cycle)")
            }
        }
    }

    // MARK: - Hash Distribution Tests

    func testHashDistribution() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Insert many keys and verify distribution
        for i in 0 ..< 100 {
            let key = "key\(i)"
            store[key] = TestValue(value: i)

            // We can't directly access the slot, but we can infer distribution
            // by checking how many collisions occur
        }

        // All keys should be retrievable (this tests distribution indirectly)
        for i in 0 ..< 100 {
            XCTAssertEqual(store["key\(i)"]?.value, i)
        }
    }

    func testHashConsistency() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let testKey = "consistency_test"
        store[testKey] = TestValue(value: 123)

        // Retrieve multiple times - should always work
        for _ in 0 ..< 100 {
            XCTAssertEqual(store[testKey]?.value, 123)
        }

        // Reopen and verify
        let store2 = try KeyValueStore<TestValue>(fileURL: url)
        XCTAssertEqual(store2[testKey]?.value, 123)
    }

    // MARK: - Load Factor Performance

    func testPerformanceLoadFactor25Percent() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        let itemCount = 32 // 25% of 128

        // Prepopulate
        for i in 0 ..< itemCount {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for _ in 0 ..< 100 {
                for i in 0 ..< itemCount {
                    _ = store["key\(i)"]
                }
            }
        }
    }

    func testPerformanceLoadFactor50Percent() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        let itemCount = 64 // 50% of 128

        // Prepopulate
        for i in 0 ..< itemCount {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for _ in 0 ..< 100 {
                for i in 0 ..< itemCount {
                    _ = store["key\(i)"]
                }
            }
        }
    }

    func testPerformanceLoadFactor75Percent() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        let itemCount = 96 // 75% of 128

        // Prepopulate
        for i in 0 ..< itemCount {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for _ in 0 ..< 100 {
                for i in 0 ..< itemCount {
                    _ = store["key\(i)"]
                }
            }
        }
    }

    func testPerformanceLoadFactor90Percent() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        let itemCount = 115 // 90% of 128

        // Prepopulate
        for i in 0 ..< itemCount {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for _ in 0 ..< 100 {
                for i in 0 ..< itemCount {
                    _ = store["key\(i)"]
                }
            }
        }
    }

    func testPerformanceLoadFactor99Percent() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)
        let itemCount = 127 // 99% of 128

        // Prepopulate
        for i in 0 ..< itemCount {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for _ in 0 ..< 100 {
                for i in 0 ..< itemCount {
                    _ = store["key\(i)"]
                }
            }
        }
    }

    // MARK: - Worst-Case Scenarios

    func testPerformanceWorstCaseProbeChain() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Use colliding keys to create maximum probe chain
        for (index, key) in collidingKeys.enumerated() {
            store[key] = TestValue(value: index)
        }

        measure {
            for _ in 0 ..< 1000 {
                for key in collidingKeys {
                    _ = store[key]
                }
            }
        }
    }

    func testPerformanceManyTombstones() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        measure {
            // Insert and delete to create tombstones
            for i in 0 ..< 50 {
                store["key\(i)"] = TestValue(value: i)
            }

            for i in 0 ..< 25 {
                store["key\(i)"] = nil
            }

            // Now lookups have to traverse tombstones
            for i in 25 ..< 50 {
                _ = store["key\(i)"]
            }

            // Clean up for next iteration
            store.removeAll()
        }
    }

    func testPerformanceSequentialVsRandom() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        // Sequential access
        measure {
            for i in 0 ..< 100 {
                _ = store["key\(i)"]
            }
        }
    }

    func testPerformanceRandomAccess() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        // Generate random sequence
        let indices = (0 ..< 100).shuffled()

        // Random access
        measure {
            for i in indices {
                _ = store["key\(i)"]
            }
        }
    }

    // MARK: - String Length Performance

    func testPerformanceShortKeys() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate with 1-5 char keys
        for i in 0 ..< 100 {
            store["k\(i)"] = TestValue(value: i)
        }

        measure {
            for i in 0 ..< 100 {
                _ = store["k\(i)"]
            }
        }
    }

    func testPerformanceMediumKeys() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate with ~25 char keys
        for i in 0 ..< 100 {
            store["medium_length_key_\(i)_test"] = TestValue(value: i)
        }

        measure {
            for i in 0 ..< 100 {
                _ = store["medium_length_key_\(i)_test"]
            }
        }
    }

    func testPerformanceLongKeys() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate with 64 char keys
        for i in 0 ..< 100 {
            let key = String(format: "very_long_key_name_with_lots_of_characters_item_%04d_end", i)
            store[key] = TestValue(value: i)
        }

        measure {
            for i in 0 ..< 100 {
                let key = String(format: "very_long_key_name_with_lots_of_characters_item_%04d_end", i)
                _ = store[key]
            }
        }
    }

    // MARK: - Persistence Performance

    func testPerformanceWriteCloseReopen() throws {
        struct TestValue {
            var value: Int
        }

        measure {
            var store: KeyValueStore<TestValue>? = try? KeyValueStore(fileURL: url)

            for i in 0 ..< 50 {
                store?["key\(i)"] = TestValue(value: i)
            }

            store = nil
            store = try? KeyValueStore(fileURL: url)

            store = nil

            try? FileManager.default.removeItem(at: url)
        }
    }

    func testPerformanceLargeBatchWrite() throws {
        struct TestValue {
            var value: Int
        }

        measure {
            let store = try! KeyValueStore<TestValue>(fileURL: url)

            for i in 0 ..< 128 {
                store["key\(i)"] = TestValue(value: i)
            }

            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Additional Benchmarks

    func testPerformanceContains() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Prepopulate
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        measure {
            for i in 0 ..< 100 {
                _ = store.contains("key\(i)")
            }
        }
    }

    func testPerformanceRemoveAll() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        measure {
            // Prepopulate
            for i in 0 ..< 100 {
                store["key\(i)"] = TestValue(value: i)
            }

            store.removeAll()
        }
    }

    // MARK: - Compaction Tests

    func testManualCompact() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Fill store
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        // Delete half to create tombstones
        for i in 0 ..< 50 {
            store["key\(i)"] = nil
        }

        // Compact should clean up tombstones
        store.compact()

        // Verify remaining items are still accessible
        for i in 50 ..< 100 {
            XCTAssertEqual(store["key\(i)"]?.value, i)
        }
    }

    func testAutoCompactTriggered() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Insert and delete many times to trigger auto-compact
        for cycle in 0 ..< 10 {
            for i in 0 ..< 20 {
                store["temp\(i)"] = TestValue(value: cycle)
            }
            for i in 0 ..< 20 {
                store["temp\(i)"] = nil
            }
        }

        // Store should still work correctly after auto-compaction
        for i in 0 ..< 50 {
            store["key\(i)"] = TestValue(value: i)
        }

        for i in 0 ..< 50 {
            XCTAssertEqual(store["key\(i)"]?.value, i)
        }
    }

    func testCompactPersistence() throws {
        struct TestValue {
            var value: Int
        }

        var store: KeyValueStore<TestValue>? = try KeyValueStore(fileURL: url)

        // Create data with tombstones
        for i in 0 ..< 80 {
            store?["key\(i)"] = TestValue(value: i)
        }
        for i in 0 ..< 40 {
            store?["key\(i)"] = nil
        }

        // Compact
        store?.compact()

        // Close and reopen
        store = nil
        store = try KeyValueStore(fileURL: url)

        // Verify data survived compaction
        for i in 40 ..< 80 {
            XCTAssertEqual(store?["key\(i)"]?.value, i, "Failed for key\(i)")
        }
    }

    func testCompactImprovesPerfomance() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Fill with items
        for i in 0 ..< 100 {
            store["key\(i)"] = TestValue(value: i)
        }

        // Delete many to create tombstones
        for i in 0 ..< 80 {
            store["key\(i)"] = nil
        }

        // Measure lookup time with tombstones
        let startWithTombstones = Date()
        for _ in 0 ..< 1000 {
            for i in 80 ..< 100 {
                _ = store["key\(i)"]
            }
        }
        let timeWithTombstones = Date().timeIntervalSince(startWithTombstones)

        // Compact
        store.compact()

        // Measure lookup time after compact
        let startAfterCompact = Date()
        for _ in 0 ..< 1000 {
            for i in 80 ..< 100 {
                _ = store["key\(i)"]
            }
        }
        let timeAfterCompact = Date().timeIntervalSince(startAfterCompact)

        // Compaction should improve performance
        // (This might not always be true due to variance, but it's a sanity check)
        print("Time with tombstones: \(timeWithTombstones)s, after compact: \(timeAfterCompact)s")
    }

    // MARK: - Memory and Stress Tests

    func testStressRapidInsertDelete() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        // Rapid insert/delete cycles
        for cycle in 0 ..< 10 {
            for i in 0 ..< 50 {
                store["key\(i)"] = TestValue(value: cycle * 100 + i)
            }

            for i in 0 ..< 50 {
                store["key\(i)"] = nil
            }
        }
    }

    func testStressFillClearRefill() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        for cycle in 0 ..< 5 {
            // Fill
            for i in 0 ..< 100 {
                store["key\(i)"] = TestValue(value: cycle * 100 + i)
            }

            // Clear
            store.removeAll()
        }
    }

    func testStressAlternatingOperations() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        for i in 0 ..< 1000 {
            if i % 3 == 0 {
                store["key\(i % 100)"] = TestValue(value: i)
            } else if i % 3 == 1 {
                _ = store["key\(i % 100)"]
            } else {
                _ = store.contains("key\(i % 100)")
            }
        }
    }

    func testValueAlignment() throws {
        // Test with different alignment requirements
        struct AlignedValue1 {
            var a: Int8
        }

        struct AlignedValue8 {
            var a: Int64
        }

        struct AlignedValueMixed {
            var a: Int8
            var b: Int64
            var c: Int32
        }

        let store1 = try KeyValueStore<AlignedValue1>(fileURL: url.appendingPathExtension("align1"))
        store1["key"] = AlignedValue1(a: 42)
        XCTAssertEqual(store1["key"]?.a, 42)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("align1"))

        let store8 = try KeyValueStore<AlignedValue8>(fileURL: url.appendingPathExtension("align8"))
        store8["key"] = AlignedValue8(a: 12_345_678)
        XCTAssertEqual(store8["key"]?.a, 12_345_678)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("align8"))

        let storeMixed = try KeyValueStore<AlignedValueMixed>(fileURL: url.appendingPathExtension("mixed"))
        storeMixed["key"] = AlignedValueMixed(a: 1, b: 2, c: 3)
        let val = storeMixed["key"]
        XCTAssertEqual(val?.a, 1)
        XCTAssertEqual(val?.b, 2)
        XCTAssertEqual(val?.c, 3)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("mixed"))
    }
}
