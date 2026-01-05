import XCTest

@testable import MemoryMap

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 2.0, *)
final class TupleStorageTests: XCTestCase {
  // MARK: - Storage Size Tests

  func testByteStorage60Size() {
    let stride = MemoryLayout<ByteStorage60.Storage>.stride
    let size = MemoryLayout<ByteStorage60.Storage>.size

    XCTAssertEqual(stride, 60, "Storage stride should be exactly 60 bytes")
    XCTAssertEqual(size, 60, "Storage size should be exactly 60 bytes")
  }

  func testByteStorage1020Size() {
    let stride = MemoryLayout<ByteStorage1020.Storage>.stride
    let size = MemoryLayout<ByteStorage1020.Storage>.size

    XCTAssertEqual(stride, 1020, "Storage stride should be exactly 1020 bytes")
    XCTAssertEqual(size, 1020, "Storage size should be exactly 1020 bytes")
  }

  func testCapacityProperty() {
    XCTAssertEqual(ByteStorage60.capacity, 60)
    XCTAssertEqual(ByteStorage1020.capacity, 1020)
  }

  // MARK: - Storage Creation Tests

  func testMakeCreatesZeroFilledStorage() {
    let storage = ByteStorage1020.make()

    // Verify all bytes are zero
    withUnsafeBytes(of: storage) { ptr in
      let bytes = ptr.bindMemory(to: Int8.self)
      for i in 0..<1020 {
        XCTAssertEqual(bytes[i], 0, "Byte at index \(i) should be zero")
      }
    }
  }

  func testMakeCreatesCorrectSize() {
    let storage = ByteStorage1020.make()
    let size = MemoryLayout.size(ofValue: storage)
    XCTAssertEqual(size, 1020)
  }

  // MARK: - Storage Manipulation Tests

  func testStorageCanStoreAndRetrieveData() {
    var storage = ByteStorage1020.make()

    // Write some test data directly
    withUnsafeMutableBytes(of: &storage) { ptr in
      let buffer = ptr.bindMemory(to: UInt8.self)
      // Write some data
      for i in 0..<10 {
        buffer[i] = UInt8(i)
      }
    }

    // Read and verify
    withUnsafeBytes(of: storage) { ptr in
      let buffer = ptr.bindMemory(to: UInt8.self)
      for i in 0..<10 {
        XCTAssertEqual(buffer[i], UInt8(i))
      }
    }
  }

  func testStorageCanStoreMaximumContent() {
    var storage = ByteStorage1020.make()
    let capacity = ByteStorage1020.capacity

    // Write maximum content
    withUnsafeMutableBytes(of: &storage) { ptr in
      let buffer = ptr.bindMemory(to: UInt8.self)
      for i in 0..<capacity {
        buffer[i] = UInt8(i % 256)
      }
    }

    // Verify
    withUnsafeBytes(of: storage) { ptr in
      let buffer = ptr.bindMemory(to: UInt8.self)
      for i in 0..<capacity {
        XCTAssertEqual(buffer[i], UInt8(i % 256))
      }
    }
  }

  // MARK: - BasicType1024 Integration Tests

  func testBasicType1024UsesCorrectStorageSize() {
    // BasicType1024 has: kind (UInt8, 1 byte) + length (UInt16, 2 bytes) + value (1020 bytes)
    // With alignment, total should be around 1023-1024 bytes
    let basicTypeSize = MemoryLayout<BasicType1024>.size

    // Verify the storage component is 1020 bytes
    XCTAssertEqual(MemoryLayout<ByteStorage1020.Storage>.size, 1020)

    // BasicType1024 size should be at least kind + length + storage
    let minimumSize = MemoryLayout<BasicType1024.Kind>.size + MemoryLayout<UInt16>.size + 1020
    XCTAssertGreaterThanOrEqual(basicTypeSize, minimumSize)
  }

  func testBasicType1024Alignment() {
    // Verify BasicType1024 is properly aligned
    let alignment = MemoryLayout<BasicType1024>.alignment
    XCTAssertGreaterThanOrEqual(alignment, 1)
  }

  // MARK: - Edge Case Tests

  func testStorageIsValueType() {
    let storage1 = ByteStorage1020.make()
    var storage2 = storage1

    // Modify storage2
    withUnsafeMutableBytes(of: &storage2) { ptr in
      ptr.storeBytes(of: UInt16(42), toByteOffset: 0, as: UInt16.self)
    }

    // Verify storage1 is unchanged (value semantics)
    withUnsafeBytes(of: storage1) { ptr in
      let value = ptr.loadUnaligned(fromByteOffset: 0, as: UInt16.self)
      XCTAssertEqual(value, 0, "Original storage should be unchanged")
    }
  }

  func testMultipleStorageInstances() {
    // Create multiple independent storage instances
    let storage1 = ByteStorage1020.make()
    let storage2 = ByteStorage1020.make()
    let storage3 = ByteStorage1020.make()

    XCTAssertEqual(MemoryLayout.size(ofValue: storage1), 1020)
    XCTAssertEqual(MemoryLayout.size(ofValue: storage2), 1020)
    XCTAssertEqual(MemoryLayout.size(ofValue: storage3), 1020)
  }
}
