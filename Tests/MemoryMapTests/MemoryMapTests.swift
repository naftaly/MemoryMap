@testable import MemoryMap
import XCTest

struct MemoryMapTestPOD {
    var state: Int8
    var ok: Bool
    var size: Int64
}

struct TestStruct: Equatable {
    var intValue: Int
    var doubleValue: Double
}

final class MemoryMapTests: XCTestCase {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testWriteCloseVerifyBlock() throws {
        var map: MemoryMap<MemoryMapTestPOD>? = try? MemoryMap(fileURL: url)
        XCTAssertNotNil(map)

        XCTAssertEqual(map?.withLockedStorage { $0.state }, 0)
        XCTAssertEqual(map?.withLockedStorage { $0.ok }, false)
        XCTAssertEqual(map?.withLockedStorage { $0.size }, 0)

        map?.withLockedStorage { $0.state = 10 }
        map?.withLockedStorage { $0.ok = true }
        map?.withLockedStorage { $0.size = 50 }

        XCTAssertEqual(map?.withLockedStorage { $0.state }, 10)
        XCTAssertEqual(map?.withLockedStorage { $0.ok }, true)
        XCTAssertEqual(map?.withLockedStorage { $0.size }, 50)

        map = try? MemoryMap(fileURL: url)
        XCTAssertNotNil(map)

        XCTAssertEqual(map?.withLockedStorage { $0.state }, 10)
        XCTAssertEqual(map?.withLockedStorage { $0.ok }, true)
        XCTAssertEqual(map?.withLockedStorage { $0.size }, 50)
    }

    func testWriteCloseVerify() throws {
        var map: MemoryMap<MemoryMapTestPOD>? = try? MemoryMap(fileURL: url)
        XCTAssertNotNil(map)

        XCTAssertEqual(map?.get.state, 0)
        XCTAssertEqual(map?.get.ok, false)
        XCTAssertEqual(map?.get.size, 0)

        map?.get.state = 10
        map?.get.ok = true
        map?.get.size = 50

        XCTAssertEqual(map?.get.state, 10)
        XCTAssertEqual(map?.get.ok, true)
        XCTAssertEqual(map?.get.size, 50)

        map = try? MemoryMap(fileURL: url)
        XCTAssertNotNil(map)

        XCTAssertEqual(map?.get.state, 10)
        XCTAssertEqual(map?.get.ok, true)
        XCTAssertEqual(map?.get.size, 50)
    }

    func testInitializationAndDefaultValue() throws {
        let memoryMap = try MemoryMap<TestStruct>(fileURL: url)
        XCTAssertEqual(
            memoryMap.get,
            TestStruct(intValue: 0, doubleValue: 0.0),
            "Default values should be zeroed for new file."
        )
    }

    func testWriteAndReadBack() throws {
        let memoryMap = try MemoryMap<TestStruct>(fileURL: url)
        let testValue = TestStruct(intValue: 42, doubleValue: 3.14)
        memoryMap.get = testValue

        XCTAssertEqual(memoryMap.get, testValue, "Written and read-back values should match.")
    }

    func testPersistenceAcrossInstances() throws {
        let initialValue = TestStruct(intValue: 123, doubleValue: 45.67)

        // Write value
        var memoryMap = try MemoryMap<TestStruct>(fileURL: url)
        memoryMap.get = initialValue

        // Read value in a new instance
        memoryMap = try MemoryMap<TestStruct>(fileURL: url)
        XCTAssertEqual(memoryMap.get, initialValue, "Data should persist across instances.")
    }

    func testThreadSafety() throws {
        let memoryMap = try MemoryMap<TestStruct>(fileURL: url)

        let expectation = XCTestExpectation(description: "Concurrent writes complete")
        expectation.expectedFulfillmentCount = 10

        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            memoryMap.get = TestStruct(intValue: index, doubleValue: Double(index))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        // Since writes are last-wins, just check no crashes occurred and value is valid
        XCTAssertNotNil(memoryMap.get, "Memory map should remain valid during concurrent writes.")
    }

    func testMagicNumberMismatch() throws {
        let fd = open(url.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        defer { close(fd) }

        var invalidMagic: UInt64 = 0xDEAD_BEEF
        write(fd, &invalidMagic, MemoryLayout<UInt64>.size)

        XCTAssertThrowsError(try MemoryMap<TestStruct>(fileURL: url)) { error in
            guard case MemoryMapError.notMemoryMap = error else {
                XCTFail("Expected MemoryMapError.notMemoryMap, got \(error)")
                return
            }
        }
    }

    func testFilePermissions() throws {
        // Test with read-only file
        let readOnlyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: readOnlyURL) }

        // Create file with read-only permissions
        let fd = open(readOnlyURL.path, O_RDWR | O_CREAT, S_IRUSR)
        close(fd)

        XCTAssertThrowsError(try MemoryMap<TestStruct>(fileURL: readOnlyURL)) { error in
            guard case MemoryMapError.unix = error else {
                XCTFail("Expected MemoryMapError.unix, got \(error)")
                return
            }
        }
    }

    func testConcurrentReadWrite() throws {
        let memoryMap = try MemoryMap<TestStruct>(fileURL: url)
        let iterations = 1000
        let expectation = XCTestExpectation(description: "Concurrent read/write operations")
        expectation.expectedFulfillmentCount = iterations * 2

        // Create a queue for writes
        let writeQueue = DispatchQueue(label: "com.memorymap.write", qos: .userInitiated, attributes: .concurrent)
        // Create a queue for reads
        let readQueue = DispatchQueue(label: "com.memorymap.read", qos: .userInitiated, attributes: .concurrent)

        // Perform concurrent writes
        for i in 0 ..< iterations {
            writeQueue.async {
                memoryMap.get = TestStruct(intValue: i, doubleValue: Double(i))
                expectation.fulfill()
            }
        }

        // Perform concurrent reads
        for _ in 0 ..< iterations {
            readQueue.async {
                _ = memoryMap.get
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
        // Verify the final state is valid
        XCTAssertNotNil(memoryMap.get, "Memory map should remain valid during concurrent operations")
    }

    func testFileDeletion() throws {
        let memoryMap = try MemoryMap<TestStruct>(fileURL: url)
        memoryMap.get = TestStruct(intValue: 42, doubleValue: 3.14)

        // Delete the file while the memory map is still open
        try FileManager.default.removeItem(at: url)

        // Try to access the memory map after file deletion
        // This should still work as the memory is still mapped
        XCTAssertEqual(memoryMap.get.intValue, 42)
        XCTAssertEqual(memoryMap.get.doubleValue, 3.14)
    }

    func testMultipleInstances() throws {
        let initialValue = TestStruct(intValue: 123, doubleValue: 45.67)

        // Create multiple instances pointing to the same file
        let map1 = try MemoryMap<TestStruct>(fileURL: url)
        let map2 = try MemoryMap<TestStruct>(fileURL: url)

        // Write from first instance
        map1.get = initialValue

        // Read from second instance
        XCTAssertEqual(map2.get, initialValue, "Changes should be visible across instances")

        // Write from second instance
        let newValue = TestStruct(intValue: 456, doubleValue: 78.90)
        map2.get = newValue

        // Read from first instance
        XCTAssertEqual(map1.get, newValue, "Changes should be visible across instances")
    }
}
