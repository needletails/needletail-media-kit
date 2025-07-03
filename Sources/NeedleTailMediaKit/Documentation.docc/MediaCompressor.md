# MediaCompressor

Video compression capabilities using AVFoundation

## Overview

The `MediaCompressor` actor provides video compression capabilities using AVFoundation's export capabilities. It's designed for high-performance video compression with configurable quality presets and progress reporting.

## Topics

### Essentials

- [Initialization](#initialization)
- [Compression](#compression)

### Advanced

- [Progress Reporting](#progress-reporting)
- [Error Handling](#error-handling)
- [Batch Processing](#batch-processing)

## Initialization

Create a new MediaCompressor instance:

```swift
let compressor = MediaCompressor()
```

The MediaCompressor is implemented as an actor, ensuring thread-safe operations across multiple concurrent compression tasks.

## Compression

### Basic Compression

Compress a video file using the specified preset and parameters:

```swift
let compressedURL = try await compressor.compressMedia(
    inputURL: videoURL,
    presetName: .resolution1920x1080,
    originalResolution: CGSize(width: 3840, height: 2160),
    fileType: .mp4,
    outputFileType: .mp4
)
```

### Compression Presets

| Preset | Resolution | Bitrate | Use Case |
|--------|------------|---------|----------|
| `.lowQuality` | 320×240 | ~500 kbps | Thumbnails, previews |
| `.mediumQuality` | 640×360 | ~1 Mbps | Web streaming |
| `.highestQuality` | 1920×1080 | ~5 Mbps | HD content |
| `.hevcHighestQuality` | 3840×2160 | ~20 Mbps | 4K content |
| `.resolution1920x1080` | 1920×1080 | ~8 Mbps | Standard HD |
| `.resolution3840x2160` | 3840×2160 | ~25 Mbps | 4K UHD |

## Progress Reporting

Monitor compression progress for long-running operations:

```swift
for await progress in compressor.compressWithProgress(...) {
    updateUI(progress: progress)
}
```

## Error Handling

The MediaCompressor throws `CompressionErrors` for various failure scenarios:

```swift
enum CompressionErrors: Error, Sendable {
    case invalidInputURL
    case unsupportedFileType
    case compressionFailed(String)
    case exportSessionCreationFailed
    case exportSessionFailed(String)
    case outputFileCreationFailed
    case insufficientDiskSpace
    case memoryAllocationFailed
}
```

## Batch Processing

Process multiple videos concurrently:

```swift
let urls = [video1URL, video2URL, video3URL]
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

## See Also

- [ImageProcessor](ImageProcessor.md) - Image processing capabilities
- [MetalProcessor](MetalProcessor.md) - GPU-accelerated processing
- [Performance Optimization](PerformanceOptimization.md) - Performance tuning 