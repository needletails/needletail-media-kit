# NeedleTail Media Kit

A high-performance media processing library for iOS and macOS with video compression, image processing, and GPU acceleration.

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2016%2B%20%7C%20macOS%2013%2B-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- **Video Compression**: High-performance video compression with multiple quality presets
- **Image Processing**: Advanced image processing with Core Image and Accelerate frameworks
- **Metal GPU Acceleration**: GPU-accelerated image processing using Metal
- **GPU Acceleration**: Metal-based image processing for optimal performance
- **Swift Concurrency**: Modern async/await support with actor-based thread safety

## Requirements

- iOS 16.0+ / macOS 13.0+
- Swift 6.0+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/needletails/needletail-media-kit.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["NeedleTailMediaKit"]
    )
]
```

Or in Xcode:
1. **File** → **Add Package Dependencies**
2. Enter: `https://github.com/needletails/needletail-media-kit.git`
3. Select version and add to your target

## Overview

NeedleTail Media Kit is a high-performance, enterprise-ready media processing library designed for mission-critical applications requiring real-time video compression, advanced image processing, and GPU-accelerated operations. Built with Swift concurrency and Metal integration, it delivers exceptional performance for enterprise-scale media workflows.

### Key Capabilities

- **Real-time Video Compression**: Multi-format video compression with configurable quality presets
- **GPU-Accelerated Processing**: Metal-based image processing for optimal performance
- **Advanced Image Operations**: Professional-grade filters, effects, and transformations
- **GPU Acceleration**: Metal-based image processing for optimal performance
- **Enterprise Concurrency**: Actor-based architecture with full Swift concurrency support
- **Cross-Platform**: Unified API for iOS and macOS applications

## Documentation

### Getting Started

- [Getting Started](GettingStarted.md) - Quick start guide
- [Installation](Deployment.md) - How to add the library to your project

### Core Components

- [MediaCompressor](MediaCompressor.md) - Video compression API
- [ImageProcessor](ImageProcessor.md) - Image processing API
- [API Reference](API_REFERENCE.md) - Complete API documentation

### Advanced Usage

- [Performance Optimization](PerformanceOptimization.md) - Performance optimization techniques
- [Enterprise Integration](EnterpriseIntegration.md) - Integration patterns for enterprise applications 

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

NeedleTail Media Kit is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/needletails/needletail-media-kit/issues)
- **Documentation**: [DocC Documentation](Documentation.docc/)
- **Email**: support@needletail.com 
