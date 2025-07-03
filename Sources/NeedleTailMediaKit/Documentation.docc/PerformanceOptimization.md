# Performance Optimization

Optimize performance when using NeedleTail Media Kit.

## Overview

This guide covers performance optimization techniques when using the NeedleTail Media Kit API.

## Concurrency

### Concurrent Processing

Use concurrent processing for better performance:

```swift
// Thread-safe concurrent operations
let compressor = MediaCompressor()
let processor = ImageProcessor()

// Concurrent processing
async let videoTask = compressor.compressMedia(
    inputURL: videoURL,
    presetName: .mediumQuality,
    originalResolution: CGSize(width: 1920, height: 1080),
    fileType: .mp4,
    outputFileType: .mp4
)

async let imageTask = processor.resizeImage(
    imageData,
    to: CGSize(width: 800, height: 600)
)

let results = try await (videoTask, imageTask)
```

### Batch Processing

Process multiple items efficiently:

```swift
let results = try await withThrowingTaskGroup(of: ProcessedImage.self) { group in
    for image in images {
        group.addTask {
            try await processor.resizeImage(image, to: CGSize(width: 800, height: 600))
        }
    }
    return try await group.reduce(into: []) { $0.append($1) }
}
```

## Resource Management

### Reuse Components

Reuse expensive components instead of creating new ones:

```swift
// Good: Reuse components
let processor = ImageProcessor()
for image in images {
    let processed = try await processor.resizeImage(image, to: targetSize)
    // Processor is reused, not recreated
}

// Avoid: Creating new components for each operation
for image in images {
    let processor = ImageProcessor() // Don't do this
    let processed = try await processor.resizeImage(image, to: targetSize)
}
```

### Memory Management

Use autorelease pools for large operations:

```swift
// Process large batches with memory management
for batch in imageBatches {
    autoreleasepool {
        for image in batch {
            let processed = try await processor.resizeImage(image, to: targetSize)
            // Memory is released after each iteration
        }
    }
}
```

## Configuration

### Performance Configuration

Configure performance parameters:

```swift
struct PerformanceConfiguration {
    let maxConcurrentOperations: Int
    let memoryLimit: Int64
    let enableCompression: Bool
    let compressionQuality: Float
    
    static let production = PerformanceConfiguration(
        maxConcurrentOperations: 10,
        memoryLimit: 2 * 1024 * 1024 * 1024, // 2GB
        enableCompression: true,
        compressionQuality: 0.8
    )
    
    static let highPerformance = PerformanceConfiguration(
        maxConcurrentOperations: 20,
        memoryLimit: 4 * 1024 * 1024 * 1024, // 4GB
        enableCompression: true,
        compressionQuality: 0.9
    )
}
```

## Best Practices

### 1. Use Appropriate Concurrency Levels

```swift
// Good: Appropriate concurrency for the task
let results = try await withThrowingTaskGroup(of: URL.self) { group in
    for url in urls {
        group.addTask {
            try await compressor.compressMedia(
                inputURL: url,
                presetName: .mediumQuality,
                originalResolution: CGSize(width: 1920, height: 1080),
                fileType: .mp4,
                outputFileType: .mp4
            )
        }
    }
    return try await group.reduce(into: [URL]()) { $0.append($1) }
}
```

### 2. Monitor Performance

```swift
// Monitor performance in production
let startTime = CFAbsoluteTimeGetCurrent()
let result = try await processor.resizeImage(imageData, to: targetSize)
let duration = CFAbsoluteTimeGetCurrent() - startTime

print("Processing time: \(duration)s")
```

### 3. Handle Errors Efficiently

```swift
// Efficient error handling
do {
    let result = try await processor.process(data)
} catch CompressionErrors.insufficientDiskSpace {
    // Handle specific errors efficiently
    cleanupTemporaryFiles()
} catch {
    // Log and continue
    print("Processing failed: \(error)")
}
```

## See Also

- [Getting Started](GettingStarted.md) - Quick start guide
- [API Reference](API_REFERENCE.md) - Complete API documentation
- [MediaCompressor](MediaCompressor.md) - Video compression API
- [ImageProcessor](ImageProcessor.md) - Image processing API 