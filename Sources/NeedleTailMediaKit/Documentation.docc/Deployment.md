# Deployment

How to integrate NeedleTail Media Kit into your applications.

## Overview

This guide covers how to add NeedleTail Media Kit to your project and start using the API.

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

### Import the Library

```swift
import NeedleTailMediaKit
```

## Basic Usage

### Video Compression

```swift
let compressor = MediaCompressor()

let compressedURL = try await compressor.compressMedia(
    inputURL: videoURL,
    presetName: .resolution1920x1080,
    originalResolution: CGSize(width: 3840, height: 2160),
    fileType: .mp4,
    outputFileType: .mp4
)
```

### Image Processing

```swift
if #available(macOS 13.0, iOS 16.0, *) {
    let processor = ImageProcessor()
    
    let processedData = try await processor
        .resizeImage(imageData, to: CGSize(width: 800, height: 600))
        .applyBlur(radius: 2.0)
        .applySepia(intensity: 0.3)
}
```

## Error Handling

Handle errors appropriately in your application:

```swift
do {
    let result = try await processor.process(data)
} catch CompressionErrors.insufficientDiskSpace {
    // Handle disk space issues
    cleanupTemporaryFiles()
} catch CompressionErrors.memoryAllocationFailed {
    // Handle memory issues
    reduceConcurrency()
} catch {
    // Log and report unknown errors
    print("Processing failed: \(error)")
}
```

## See Also

- [Getting Started](GettingStarted.md) - Quick start guide
- [API Reference](API_REFERENCE.md) - Complete API documentation
- [MediaCompressor](MediaCompressor.md) - Video compression API
- [ImageProcessor](ImageProcessor.md) - Image processing API 
