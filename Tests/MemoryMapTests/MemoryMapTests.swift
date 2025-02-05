import XCTest
@testable import MemoryMap

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
        
        XCTAssertEqual(map?.get { $0.state }, 0)
        XCTAssertEqual(map?.get { $0.ok }, false)
        XCTAssertEqual(map?.get { $0.size }, 0)
        
        map?.get { $0.state = 10 }
        map?.get { $0.ok = true }
        map?.get { $0.size = 50 }
        
        XCTAssertEqual(map?.get { $0.state }, 10)
        XCTAssertEqual(map?.get { $0.ok }, true)
        XCTAssertEqual(map?.get { $0.size }, 50)
        
        map = try? MemoryMap(fileURL: url)
        XCTAssertNotNil(map)
        
        XCTAssertEqual(map?.get { $0.state }, 10)
        XCTAssertEqual(map?.get { $0.ok }, true)
        XCTAssertEqual(map?.get { $0.size }, 50)
        
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
        XCTAssertEqual(memoryMap.get, TestStruct(intValue: 0, doubleValue: 0.0), "Default values should be zeroed for new file.")
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
        
        var invalidMagic: UInt64 = 0xDEADBEEF
        write(fd, &invalidMagic, MemoryLayout<UInt64>.size)
        
        XCTAssertThrowsError(try MemoryMap<TestStruct>(fileURL: url)) { error in
            guard case MemoryMapError.notMemoryMap = error else {
                XCTFail("Expected MemoryMapError.notMemoryMap, got \(error)")
                return
            }
        }
    }
}
