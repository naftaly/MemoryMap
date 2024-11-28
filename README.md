
# Welcome to MemoryMap! 🚀

[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-5.5-orange.svg)](https://swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey.svg)]()

MemoryMap is a Swift utility class designed for efficient persistence and crash-resilient storage of Plain Old Data (POD) structs using memory-mapped files. It provides thread-safe access to the stored data, ensuring integrity and performance for applications requiring low-latency storage solutions.

## 🌟 Features

- **Memory-mapped file support**: Back a POD struct with a memory-mapped file for direct memory access.
- **Thread-safe access**: Read and write operations are protected by a locking mechanism.
- **Crash resilience**: Changes are immediately reflected in the memory-mapped file.
- **Data integrity validation**: Validates the file using a magic number.

## 🔧 Installation

To get started with MemoryMap, integrate it directly into your project:

1. In Xcode, select **File** > **Swift Packages** > **Add Package Dependency...**
2. Enter the repository URL `https://github.com/naftaly/memorymap.git`.
3. Specify the version or branch you want to use.
4. Follow the prompts to complete the integration.

## 🚀 Usage

```swift
import MemoryMap

struct MyData {
    var counter: Int
    var flag: Bool
}

do {
    let fileURL = URL(fileURLWithPath: "/path/to/memory.map")
    let memoryMap = try MemoryMap<MyData>(fileURL: fileURL)
    
    // Read/write data
    memoryMap.get.counter = 42
    memoryMap.get.flag = false
} catch {
    print("Error initializing MemoryMap: \(error)")
}
```

## 👋 Contributing

Got ideas on how to make MemoryMap even better? We'd love to hear from you! Feel free to fork the repo, push your changes, and open a pull request. You can also open an issue if you run into bugs or have feature suggestions.

## 📄 License

MemoryMap is proudly open-sourced under the MIT License. Dive into the LICENSE file for more details.
