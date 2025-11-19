/// MIT License
///
/// Copyright (c) 2024 Alexander Cohen
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in all
/// copies or substantial portions of the Software.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
/// SOFTWARE.

import Foundation
import os

/// Protocol for lock implementations used by MemoryMap.
///
/// Allows choosing different locking strategies:
/// - `OSAllocatedUnfairLock` (default): Fast unfair lock for typical use
/// - `NoLock`: No-op lock for single-threaded scenarios
/// - `NSLock`: Standard Foundation lock
/// - Custom implementations for specialized needs
public protocol MemoryMapLock {
    func lock()
    func unlock()
}

/// A no-op lock implementation for single-threaded use cases.
///
/// Use this when you know MemoryMap will only be accessed from a single thread
/// to avoid lock overhead. Methods are inlined for zero-cost abstraction.
///
/// ## Example
/// ```swift
/// let memoryMap = try MemoryMap<MyData>(fileURL: url, lock: NoLock())
/// ```
public class NoLock: MemoryMapLock {
    public init() {}

    @inline(__always)
    public func lock() {}

    @inline(__always)
    public func unlock() {}
}

extension NSLock: MemoryMapLock {}
extension OSAllocatedUnfairLock: MemoryMapLock where State == () {}

/// The default lock implementation for MemoryMap
public typealias DefaultMemoryMapLock = OSAllocatedUnfairLock
