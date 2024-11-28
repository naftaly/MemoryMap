import Foundation
import Darwin
import os

/// MemoryMap is a utility class that backs a Plain Old Data (POD) struct
/// with a memory-mapped file. This enables efficient persistence and
/// crash-resilient storage, with thread-safe access.
public class MemoryMap<T>: @unchecked Sendable {
    
    /// The URL of the memory-mapped file.
    public let url: URL
    
    /// Initializes a memory-mapped file for the given POD type `T`.
    ///
    /// If the file does not exist, it will be created. If the file is smaller
    /// than the required size (`MemoryLayout<T>` + a magic number), it will be resized.
    /// A magic number is stored and validated to ensure data integrity.
    ///
    /// - Parameters:
    ///   - fileURL: The file's location on disk.
    ///
    /// Note: `T` must be a Plain Old Data (POD) type. This is validated at runtime.
    public init(fileURL: URL) throws {
        
        // only POD types are allowed, so basically
        // structs with built-in types (aka. trivial).
        assert(_isPOD(T.self), "\(type(of: T.self)) is a non-trivial Type.")
        
        // Ensure we're not creating a huge file.
        // 1MB for PODs should be plenty.
        let maxSize = 1024 * 1024
        guard MemoryLayout<MemoryMapContainer>.stride <= maxSize else {
            throw MemoryMapError.invalidSize
        }
        
        self.url = fileURL
        self.container = try Self._mmap(self.url, size: MemoryLayout<MemoryMapContainer>.stride)
        self._s = withUnsafeMutablePointer(to: &self.container.pointee._s) {
            UnsafeMutablePointer($0)
        }
    }
    
    /// Provides thread-safe access to the mapped data.
    ///
    /// This property allows reading and writing of the POD struct `T`.
    /// Changes are immediately reflected in the memory-mapped file.
    public var get: UnsafeMutablePointer<T>.Pointee {
        get {
            lock.lock()
            defer { lock.unlock() }
            return self._s.pointee
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            self._s.pointee = newValue
        }
    }
    
    // MARK: - private
    
    deinit {
        munmap(self.container, MemoryLayout<MemoryMapContainer>.stride)
    }
    
    /// Maps the specified file to memory, creating or resizing it as necessary.
    ///
    /// - Parameters:
    ///   - fileURL: The file's location on disk.
    ///   - size: The size of the memory-mapped region.
    ///
    /// - Returns: A pointer to the mapped memory.
    ///
    private static func _mmap(_ fileURL: URL, size: Int) throws -> UnsafeMutablePointer<MemoryMapContainer> {
        
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        
        // open and ensure we create if non-existant.
        // close on end of scope
        let fd = open(fileURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard fd > 0 else {
            throw MemoryMapError.unix(errno, "open", fileURL)
        }
        defer { close(fd) }
        
        // Get the file size
        var stat = stat()
        guard fstat(fd, &stat) == 0 else {
            throw MemoryMapError.unix(errno, "fstat", fileURL)
        }
        
        // resize if needed
        if stat.st_size < size {
            guard ftruncate(fd, off_t(size)) == 0 else {
                throw MemoryMapError.unix(errno, "ftruncate", fileURL)
            }
        }
        
        // map it
        let map = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_FILE | MAP_SHARED, fd, 0)
        guard map != MAP_FAILED else {
            throw MemoryMapError.unix(errno, "mmap", fileURL)
        }
        
        // Unmap when we defer.
        // if any early returns get added, an error
        // will occur if _unmapOnDefer_ isn't set.
        let unmapOnDefer: Bool
        defer { if unmapOnDefer { munmap(map, size) } }
        
        guard Int(bitPattern: map) % MemoryLayout<MemoryMapContainer>.alignment == 0 else {
            unmapOnDefer = true
            throw MemoryMapError.alignment
        }
        
        guard let pointer = map?.bindMemory(to: MemoryMapContainer.self, capacity: 1) else {
            unmapOnDefer = true
            throw MemoryMapError.failedBind
        }
        
        // This is our default magic number that
        // should be at the top of every container.
        let defaultMagic: UInt64 = 0xB10C
        
        // If the file doesn't exists, set it up with defaults
        if !fileExists {
            pointer.pointee.magic = defaultMagic
        }
        
        // ensure magic
        guard pointer.pointee.magic == defaultMagic else {
            unmapOnDefer = true
            throw MemoryMapError.notMemoryMap
        }
        
        unmapOnDefer = false
        return pointer
    }
    
    // Swift doesn't have any struct packing.
    // What it does do however is take the largest member
    // and use that for alignment.
    // So in theory, if we start a struct with 64 bits,
    // each member should be padded to 64bit (.alignment).
    private struct MemoryMapContainer {
        var magic: UInt64
        var _s: T
    }
    
    private let lock = NSLock()
    private let container: UnsafeMutablePointer<MemoryMapContainer>
    private let _s: UnsafeMutablePointer<T>
}

public enum MemoryMapError: Error {
    
    /// A unix error of some sort (open, mmap, ...).
    case unix(Int32, String, URL)
    
    /// Memory layout alignment is incorrect.
    case alignment
    
    /// `.bindMemory` failed.
    case failedBind
    
    /// The header magic number is wrong.
    case notMemoryMap
    
    /// The struct backing the map is too big.
    case invalidSize
}
