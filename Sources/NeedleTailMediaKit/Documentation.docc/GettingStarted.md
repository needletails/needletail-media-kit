# Getting Started

Learn how to get started with NeedleTail Media Kit, from installation to your first media processing operation.

## Overview

This guide will help you get started with NeedleTail Media Kit, from installation to your first media processing operation.

## Prerequisites

Before you begin, ensure you have:

- **Xcode 15.0+** or **Swift 6.0+**
- **iOS 16.0+** or **macOS 13.0+**
- **Metal-capable device** (A9+ for iOS, any modern Mac)

## Installation

### Swift Package Manager

Add NeedleTail Media Kit to your project using Swift Package Manager:

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

### Xcode Integration

1. In Xcode, go to **File** → **Add Package Dependencies**
2. Enter the repository URL: `https://github.com/needletails/needletail-media-kit.git`
3. Select version: `Up to Next Major (1.0.0)`
4. Add to your target

## Your First Media Processing

### Basic Video Compression

```swift
import NeedleTailMediaKit

// Initialize compressor
let compressor = MediaCompressor()

// Compress video with quality preset
let compressedURL = try await compressor.compressMedia(
    inputURL: videoURL,
    presetName: .resolution1920x1080,
    originalResolution: CGSize(width: 3840, height: 2160),
    fileType: .mp4,
    outputFileType: .mp4
)
```

### Image Processing Pipeline

```swift
import NeedleTailMediaKit

if #available(macOS 13.0, iOS 16.0, *) {
    let processor = ImageProcessor()
    
    // Process image with multiple effects
    let processedImage = try await processor
        .resizeImage(imageData, to: CGSize(width: 800, height: 600))
        .applyBlur(radius: 2.0)
        .applySepia(intensity: 0.3)
}
```

## Next Steps

- [Quick Start](QuickStart.md) - Learn more advanced usage patterns
- [MediaCompressor](MediaCompressor.md) - Explore video compression capabilities
- [ImageProcessor](ImageProcessor.md) - Discover image processing features
- [Performance Optimization](PerformanceOptimization.md) - Optimize for production use 
