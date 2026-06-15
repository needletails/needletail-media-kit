# ImageProcessor

High-performance image processing using Core Image and Accelerate

## Overview

The `ImageProcessor` actor provides high-performance image processing using Core Image and Accelerate frameworks. It supports various image operations including resizing, filtering, and effects with GPU acceleration.

## Topics

### Essentials

- [Initialization](#initialization)
- [Basic Operations](#basic-operations)

### Advanced

- [Filter Pipeline](#filter-pipeline)
- [Batch Processing](#batch-processing)
- [Performance Optimization](#performance-optimization)

## Initialization

Create a new ImageProcessor instance:

```swift
@available(macOS 14.0, iOS 17.0, *)
let processor = ImageProcessor()
```

The ImageProcessor is implemented as an actor, ensuring thread-safe operations across multiple concurrent processing tasks.

## Basic Operations

### Resize Image

Resize an image while maintaining aspect ratio:

```swift
let resizedData = try await processor.resizeImage(
    imageData,
    to: CGSize(width: 800, height: 600),
    quality: .high
)
```

### Apply Blur

Apply a Gaussian blur effect to an image:

```swift
let blurredData = try await processor.applyBlur(
    to: imageData,
    radius: 5.0
)
```

### Apply Sepia

Apply a sepia tone effect to an image:

```swift
let sepiaData = try await processor.applySepia(
    to: imageData,
    intensity: 0.6
)
```

### Adjust Brightness and Contrast

Adjust the brightness and contrast of an image:

```swift
let adjustedData = try await processor.adjustBrightnessContrast(
    image: imageData,
    brightness: 0.2,
    contrast: 1.3
)
```

### Convert to Grayscale

Convert an image to grayscale:

```swift
let grayscaleData = try await processor.convertToGrayscale(imageData)
```

## Filter Pipeline

Run multiple operations as a pipeline:

```swift
let resizedData = try await processor.resizeImage(
    imageData,
    to: CGSize(width: 800, height: 600)
)
let blurredData = try await processor.applyBlur(to: resizedData, radius: 2.0)
let sepiaData = try await processor.applySepia(to: blurredData, intensity: 0.3)
let processedData = try await processor.adjustBrightnessContrast(
    image: sepiaData,
    brightness: 0.1,
    contrast: 1.2
)
```

## Batch Processing

Process multiple images concurrently:

```swift
let images = [image1Data, image2Data, image3Data]
let results = try await withThrowingTaskGroup(of: Data.self) { group in
    for image in images {
        group.addTask {
            try await processor.resizeImage(image, to: CGSize(width: 800, height: 600))
        }
    }
    return try await group.reduce(into: [Data]()) { $0.append($1) }
}
```

## Error Handling

The ImageProcessor throws `ImageErrors` for various failure scenarios:

```swift
enum ImageErrors: Error, Sendable {
    case imageCreationFailed(String)
    case imageProcessingFailed(String)
    case invalidImageData
    case unsupportedImageFormat
}
```

## Performance Optimization

### Processor Reuse

Reuse an `ImageProcessor` so its Core Image context can be reused across operations:

```swift
let blur1 = try await processor.applyBlur(to: image1, radius: 5.0)
let blur2 = try await processor.applyBlur(to: image2, radius: 5.0)
```

### Memory Management

Efficient memory management with automatic cleanup:

```swift
// Memory is managed automatically
let processed = try await processor.resizeImage(largeImageData, to: targetSize)
// Memory is released automatically when processed goes out of scope
```

## See Also

- [MediaCompressor](MediaCompressor.md) - Video compression capabilities
- [MetalProcessor](MetalProcessor.md) - GPU-accelerated processing
- [Performance Optimization](PerformanceOptimization.md) - Performance tuning 
