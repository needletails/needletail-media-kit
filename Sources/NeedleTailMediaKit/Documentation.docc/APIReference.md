# NeedleTail Media Kit - API Reference

## Table of Contents

- [Overview](#overview)
- [MediaCompressor](#mediacompressor)
- [ImageProcessor](#imageprocessor)
- [MetalProcessor](#metalprocessor)

- [Error Types](#error-types)
- [Extensions](#extensions)
- [Configuration](#configuration)

## Overview

This document provides a comprehensive reference for all public APIs in the NeedleTail Media Kit. All APIs are designed to be thread-safe and support Swift concurrency patterns.

### Conventions

- **Async/Await**: All long-running operations use async/await
- **Actor-Based**: Components are implemented as actors for thread safety
- **Error Handling**: Comprehensive error types with detailed information
- **Memory Safety**: All APIs follow Swift's memory safety guarantees

## MediaCompressor

The `MediaCompressor` actor provides video compression capabilities using AVFoundation.

### Initialization

```swift
public actor MediaCompressor {
    public init()
}
```

### Core Methods

#### compressMedia

Compresses a video file using the specified preset and parameters.

```swift
public func compressMedia(
    inputURL: URL,
    presetName: AVAssetExportPreset,
    originalResolution: CGSize,
    fileType: AVFileType,
    outputFileType: AVFileType
) async throws -> URL
```

**Parameters:**
- `inputURL`: The URL of the input video file
- `presetName`: The compression preset to use (see Compression Presets)
- `originalResolution`: The original video resolution
- `fileType`: The input file format (e.g., `.mp4`, `.mov`)
- `outputFileType`: The output file format (e.g., `.mp4`, `.mov`)

**Returns:** The URL of the compressed video file

**Throws:** `CompressionErrors` for various failure scenarios

**Example:**
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

### Compression Presets

| Preset | Resolution | Bitrate | Use Case |
|--------|------------|---------|----------|
| `.lowQuality` | 320×240 | ~500 kbps | Thumbnails, previews |
| `.mediumQuality` | 640×360 | ~1 Mbps | Web streaming |
| `.highestQuality` | 1920×1080 | ~5 Mbps | HD content |
| `.hevcHighestQuality` | 3840×2160 | ~20 Mbps | 4K content |
| `.resolution1920x1080` | 1920×1080 | ~8 Mbps | Standard HD |
| `.resolution3840x2160` | 3840×2160 | ~25 Mbps | 4K UHD |

### Error Handling

The `MediaCompressor` throws `CompressionErrors` for various failure scenarios:

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

## ImageProcessor

The `ImageProcessor` actor provides high-performance image processing using Core Image and Accelerate frameworks.

### Initialization

```swift
@available(macOS 13.0, iOS 16.0, *)
public actor ImageProcessor {
    public init()
}
```

### Core Methods

#### resizeImage

Resizes an image while maintaining aspect ratio.

```swift
public func resizeImage(
    _ image: Data,
    to targetSize: CGSize,
    quality: CGInterpolationQuality = .high
) async throws -> Data
```

**Parameters:**
- `image`: The input image data
- `targetSize`: The target size for the resized image
- `quality`: The interpolation quality (default: `.high`)

**Returns:** The resized image data

**Throws:** `ImageErrors` for processing failures

**Example:**
```swift
let processor = ImageProcessor()
let resizedData = try await processor.resizeImage(
    imageData,
    to: CGSize(width: 800, height: 600),
    quality: .high
)
```

#### applyBlur

Applies a Gaussian blur effect to an image.

```swift
public func applyBlur(
    to image: Data,
    radius: Double = 10.0
) async throws -> Data
```

**Parameters:**
- `image`: The input image data
- `radius`: The blur radius (default: 10.0)

**Returns:** The blurred image data

**Throws:** `ImageErrors` for processing failures

**Example:**
```swift
let blurredData = try await processor.applyBlur(
    to: imageData,
    radius: 5.0
)
```

#### applySepia

Applies a sepia tone effect to an image.

```swift
public func applySepia(
    to image: Data,
    intensity: Double = 0.8
) async throws -> Data
```

**Parameters:**
- `image`: The input image data
- `intensity`: The sepia intensity (0.0 to 1.0, default: 0.8)

**Returns:** The sepia-toned image data

**Throws:** `ImageErrors` for processing failures

**Example:**
```swift
let sepiaData = try await processor.applySepia(
    to: imageData,
    intensity: 0.6
)
```

#### adjustBrightnessContrast

Adjusts the brightness and contrast of an image.

```swift
public func adjustBrightnessContrast(
    image: Data,
    brightness: Double = 0.0,
    contrast: Double = 1.0
) async throws -> Data
```

**Parameters:**
- `image`: The input image data
- `brightness`: Brightness adjustment (-1.0 to 1.0, default: 0.0)
- `contrast`: Contrast adjustment (0.0 to 3.0, default: 1.0)

**Returns:** The adjusted image data

**Throws:** `ImageErrors` for processing failures

**Example:**
```swift
let adjustedData = try await processor.adjustBrightnessContrast(
    image: imageData,
    brightness: 0.2,
    contrast: 1.3
)
```

#### convertToGrayscale

Converts an image to grayscale.

```swift
public func convertToGrayscale(_ image: Data) async throws -> Data
```

**Parameters:**
- `image`: The input image data

**Returns:** The grayscale image data

**Throws:** `ImageErrors` for processing failures

**Example:**
```swift
let grayscaleData = try await processor.convertToGrayscale(imageData)
```

### Error Handling

The `ImageProcessor` throws `ImageErrors` for various failure scenarios:

```swift
enum ImageErrors: Error, Sendable {
    case imageCreationFailed(String)
    case imageProcessingFailed(String)
    case invalidImageData
    case unsupportedImageFormat
    case filterApplicationFailed(String)
    case memoryAllocationFailed
}
```

## MetalProcessor

The `MetalProcessor` actor provides GPU-accelerated image processing using Metal.

### Initialization

```swift
public actor MetalProcessor {
    public init()
}
```

### Core Methods

#### createTexture

Creates a Metal texture from a Core Video pixel buffer.

```swift
public func createTexture(
    from pixelBuffer: CVPixelBuffer,
    device: MTLDevice
) throws -> MTLTexture
```

**Parameters:**
- `pixelBuffer`: The Core Video pixel buffer
- `device`: The Metal device to create the texture on

**Returns:** The created Metal texture

**Throws:** `MetalError` for texture creation failures

**Example:**
```swift
let metalProcessor = MetalProcessor()
let texture = try metalProcessor.createTexture(
    from: pixelBuffer,
    device: MTLCreateSystemDefaultDevice()!
)
```

#### convert2VUYToCVPixelBuffer

Converts a YUV pixel buffer to RGB format.

```swift
public func convert2VUYToCVPixelBuffer(
    _ pixelBuffer: CVPixelBuffer,
    ciContext: CIContext
) async throws -> CVPixelBuffer?
```

**Parameters:**
- `pixelBuffer`: The input YUV pixel buffer
- `ciContext`: The Core Image context for processing

**Returns:** The converted RGB pixel buffer, or nil if conversion fails

**Throws:** `MetalError` for conversion failures

**Example:**
```swift
let convertedBuffer = try await metalProcessor.convert2VUYToCVPixelBuffer(
    pixelBuffer,
    ciContext: CIContext()
)
```

### Error Handling

The `MetalProcessor` throws `MetalError` for various failure scenarios:

```swift
enum MetalError: Error, Sendable {
    case deviceNotAvailable
    case textureCreationFailed
    case shaderCompilationFailed(String)
    case commandBufferCreationFailed
    case conversionFailed(String)
    case memoryAllocationFailed
}
```



## Error Types

### CompressionErrors

Errors that can occur during video compression operations.

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

### ImageErrors

Errors that can occur during image processing operations.

```swift
enum ImageErrors: Error, Sendable {
    case imageCreationFailed(String)
    case imageProcessingFailed(String)
    case invalidImageData
    case unsupportedImageFormat
    case filterApplicationFailed(String)
    case memoryAllocationFailed
}
```

### MetalError

Errors that can occur during Metal operations.

```swift
enum MetalError: Error, Sendable {
    case deviceNotAvailable
    case textureCreationFailed
    case shaderCompilationFailed(String)
    case commandBufferCreationFailed
    case conversionFailed(String)
    case memoryAllocationFailed
}
```

## Extensions

### CGSize Extension

Utility methods for CGSize operations.

```swift
extension CGSize {
    public func aspectRatio() -> CGFloat
    public func scaled(to targetSize: CGSize) -> CGSize
    public func fits(in containerSize: CGSize) -> Bool
}
```

**Example:**
```swift
let size = CGSize(width: 1920, height: 1080)
let aspectRatio = size.aspectRatio() // 16:9
let scaledSize = size.scaled(to: CGSize(width: 800, height: 600))
```

### NSImage Extension

Utility methods for NSImage operations (macOS only).

```swift
extension NSImage {
    public func resized(to size: CGSize) -> NSImage?
    public func dataRepresentation() -> Data?
}
```

**Example:**
```swift
if let image = NSImage(named: "sample"),
   let resized = image.resized(to: CGSize(width: 800, height: 600)) {
    // Use resized image
}
```

### UIView Extension

Utility methods for UIView operations (iOS only).

```swift
extension UIView {
    public func snapshot() -> UIImage?
    public func addBlurEffect(style: UIBlurEffect.Style)
}
```

**Example:**
```swift
let snapshot = view.snapshot()
view.addBlurEffect(style: .systemMaterial)
```

## Configuration

### Performance Configuration

Configure performance parameters for the media kit.

```swift
struct PerformanceConfiguration {
    let maxConcurrentOperations: Int
    let memoryLimit: Int64
    let cacheSize: Int
    let gpuMemoryLimit: Int64
    let enableCompression: Bool
    let compressionQuality: Float
    
    static let production = PerformanceConfiguration(
        maxConcurrentOperations: 10,
        memoryLimit: 2 * 1024 * 1024 * 1024, // 2GB
        cacheSize: 1000,
        gpuMemoryLimit: 1024 * 1024 * 1024, // 1GB
        enableCompression: true,
        compressionQuality: 0.8
    )
}
```

### Security Configuration

Configure security parameters for the media kit.

```swift
struct SecurityConfiguration {
    let maxFileSize: Int64
    let maxConcurrentOperations: Int
    let allowedFileTypes: Set<String>
    let maxMemoryUsage: Int64
    let enableEncryption: Bool
    
    static let production = SecurityConfiguration(
        maxFileSize: 1024 * 1024 * 1024, // 1GB
        maxConcurrentOperations: 10,
        allowedFileTypes: ["mp4", "mov", "jpg", "png", "heic"],
        maxMemoryUsage: 2 * 1024 * 1024 * 1024, // 2GB
        enableEncryption: true
    )
}
```

## Usage Examples

### Basic Video Compression

```swift
import NeedleTailMediaKit

// Initialize compressor
let compressor = MediaCompressor()

// Compress video
do {
    let compressedURL = try await compressor.compressMedia(
        inputURL: videoURL,
        presetName: .resolution1920x1080,
        originalResolution: CGSize(width: 3840, height: 2160),
        fileType: .mp4,
        outputFileType: .mp4
    )
    print("Compressed video saved to: \(compressedURL)")
} catch {
    print("Compression failed: \(error)")
}
```

### Image Processing Pipeline

```swift
import NeedleTailMediaKit

if #available(macOS 13.0, iOS 16.0, *) {
    let processor = ImageProcessor()
    
    do {
        // Process image with multiple effects
        let processedData = try await processor
            .resizeImage(imageData, to: CGSize(width: 800, height: 600))
            .applyBlur(radius: 2.0)
            .applySepia(intensity: 0.3)
        
        // Save processed image
        try processedData.write(to: outputURL)
    } catch {
        print("Image processing failed: \(error)")
    }
}
```

### Batch Processing

```swift
import NeedleTailMediaKit

// Process multiple files concurrently
let urls = [video1URL, video2URL, video3URL]
let compressor = MediaCompressor()

do {
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
    
    print("Processed \(results.count) videos")
} catch {
    print("Batch processing failed: \(error)")
}
```

### Metal Processing

```swift
import NeedleTailMediaKit
import Metal

let metalProcessor = MetalProcessor()

do {
    // Create Metal texture from pixel buffer
    let device = MTLCreateSystemDefaultDevice()!
    let texture = try metalProcessor.createTexture(
        from: pixelBuffer,
        device: device
    )
    
    // Convert YUV to RGB
    let convertedBuffer = try await metalProcessor.convert2VUYToCVPixelBuffer(
        pixelBuffer,
        ciContext: CIContext()
    )
    
    print("Metal processing completed")
} catch {
    print("Metal processing failed: \(error)")
}
```

This API reference provides comprehensive documentation for all public APIs in the NeedleTail Media Kit, including detailed parameter descriptions, return values, error handling, and usage examples. 