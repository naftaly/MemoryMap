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
        let removed = store.removeValue(forKey: "key1")
        XCTAssertEqual(removed?.value, 42)
        XCTAssertNil(store["key1"])
    }

    func testRemoveNonExistent() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        let removed = store.removeValue(forKey: "nonexistent")
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
        let removed = store.removeValue(forKey: keys[0])
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
        store.removeValue(forKey: keys[2])
        XCTAssertEqual(store[keys[1]]?.value, 2, "key b should still be accessible after deleting c")
        XCTAssertEqual(store[keys[3]]?.value, 4, "key d should still be accessible after deleting c")

        // Verify count is correct
        XCTAssertEqual(store.count, 2, "Count should be 2 after removing 2 keys")
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
        store.removeValue(forKey: keys[1])

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
        store.removeValue(forKey: keys[1])

        // Reinsert with different value
        store[keys[1]] = TestValue(value: 20)

        // All should be accessible
        XCTAssertEqual(store[keys[0]]?.value, 1)
        XCTAssertEqual(store[keys[1]]?.value, 20)
        XCTAssertEqual(store[keys[2]]?.value, 3)

        // Count should be correct
        XCTAssertEqual(store.count, 3)
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
        XCTAssertTrue(store.isEmpty)
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

        // Create a key longer than 64 bytes
        let longKey = String(repeating: "a", count: 65)

        // Subscript silently ignores too-long keys
        store[longKey] = TestValue(value: 42)
        XCTAssertNil(store[longKey])

        // But explicit set should throw
        XCTAssertThrowsError(try store.set(longKey, TestValue(value: 42))) { error in
            guard case KeyValueStoreError.keyTooLong = error else {
                XCTFail("Expected KeyValueStoreError.keyTooLong, got \(error)")
                return
            }
        }
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
        XCTAssertNil(store[overflowKey])

        // But explicit set should throw
        XCTAssertThrowsError(try store.set(overflowKey, TestValue(value: 999))) { error in
            guard case KeyValueStoreError.storeFull = error else {
                XCTFail("Expected KeyValueStoreError.storeFull, got \(error)")
                return
            }
        }
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

        // Update non-existent key returns nil
        let oldValue1 = try store.updateValue(TestValue(value: 42), forKey: "key")
        XCTAssertNil(oldValue1)
        XCTAssertEqual(store["key"]?.value, 42)

        // Update existing key returns old value
        let oldValue2 = try store.updateValue(TestValue(value: 100), forKey: "key")
        XCTAssertEqual(oldValue2?.value, 42)
        XCTAssertEqual(store["key"]?.value, 100)
    }

    func testCountAndIsEmpty() throws {
        struct TestValue {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.isEmpty)

        store["key1"] = TestValue(value: 1)
        XCTAssertEqual(store.count, 1)
        XCTAssertFalse(store.isEmpty)

        store["key2"] = TestValue(value: 2)
        store["key3"] = TestValue(value: 3)
        XCTAssertEqual(store.count, 3)

        store["key1"] = nil
        XCTAssertEqual(store.count, 2)

        store.removeAll()
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.isEmpty)
    }

    func testToDictionary() throws {
        struct TestValue: Equatable {
            var value: Int
        }

        let store = try KeyValueStore<TestValue>(fileURL: url)

        store["key1"] = TestValue(value: 1)
        store["key2"] = TestValue(value: 2)
        store["key3"] = TestValue(value: 3)

        let dict = store.toDictionary()
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
                _ = store.removeValue(forKey: "key\(i)")
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
                _ = store.count
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
            _ = store.toDictionary()
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
                _ = store.removeValue(forKey: "key\(i)")
            }

            _ = store.count
            _ = store.keys
        }
    }
}
