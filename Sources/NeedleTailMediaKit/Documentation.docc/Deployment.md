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
if #available(macOS 14.0, iOS 17.0, *) {
    let processor = ImageProcessor()
    
    let resizedData = try await processor.resizeImage(
        imageData,
        to: CGSize(width: 800, height: 600)
    )
    let blurredData = try await processor.applyBlur(to: resizedData, radius: 2.0)
    let processedData = try await processor.applySepia(to: blurredData, intensity: 0.3)
}
```

## Error Handling

Handle errors appropriately in your application:

```swift
do {
    let result = try await compressor.compressMedia(
        inputURL: videoURL,
        presetName: .mediumQuality,
        originalResolution: CGSize(width: 1920, height: 1080),
        fileType: .mp4,
        outputFileType: .mp4
    )
} catch MediaCompressor.CompressionErrors.noVideoTrack {
    // Handle unsupported input
} catch MediaCompressor.CompressionErrors.failedToCreateExportSession {
    // Retry later or fall back to stripMetadata(inputURL:outputFileType:)
} catch {
    // Log and report unknown errors
    print("Processing failed: \(error)")
}
```

## See Also

- [Getting Started](GettingStarted.md) - Quick start guide
- [API Reference](APIReference.md) - Complete API documentation
- [MediaCompressor](MediaCompressor.md) - Video compression API
- [ImageProcessor](ImageProcessor.md) - Image processing API 
