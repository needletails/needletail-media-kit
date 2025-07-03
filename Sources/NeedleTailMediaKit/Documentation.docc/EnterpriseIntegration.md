# Enterprise Integration

Integration patterns for using NeedleTail Media Kit in enterprise applications.

## Overview

This guide covers common integration patterns and best practices for using NeedleTail Media Kit in enterprise applications.

## Service Layer Pattern

Create a service layer to abstract media processing operations:

```swift
protocol MediaServiceProtocol {
    func compressVideo(_ request: VideoCompressionRequest) async throws -> VideoCompressionResponse
    func processImage(_ request: ImageProcessingRequest) async throws -> ImageProcessingResponse
}

class MediaService: MediaServiceProtocol {
    private let compressor = MediaCompressor()
    private let processor = ImageProcessor()
    
    func compressVideo(_ request: VideoCompressionRequest) async throws -> VideoCompressionResponse {
        let compressedURL = try await compressor.compressMedia(
            inputURL: request.inputURL,
            presetName: request.preset,
            originalResolution: request.resolution,
            fileType: request.inputFormat,
            outputFileType: request.outputFormat
        )
        
        return VideoCompressionResponse(outputURL: compressedURL)
    }
    
    func processImage(_ request: ImageProcessingRequest) async throws -> ImageProcessingResponse {
        let processedData = try await processor.resizeImage(
            request.imageData,
            to: request.targetSize
        )
        
        return ImageProcessingResponse(processedData: processedData)
    }
}

struct VideoCompressionRequest {
    let inputURL: URL
    let preset: AVAssetExportPreset
    let resolution: CGSize
    let inputFormat: AVFileType
    let outputFormat: AVFileType
}

struct VideoCompressionResponse {
    let outputURL: URL
}

struct ImageProcessingRequest {
    let imageData: Data
    let targetSize: CGSize
}

struct ImageProcessingResponse {
    let processedData: Data
}
```

## Dependency Injection

Use protocols for better testability and flexibility:

```swift
protocol MediaProcessorProtocol {
    func processImage(_ data: Data) async throws -> Data
}

protocol MediaCompressorProtocol {
    func compressVideo(_ url: URL) async throws -> URL
}

class MediaProcessor: MediaProcessorProtocol {
    private let processor: ImageProcessor
    
    init(processor: ImageProcessor = ImageProcessor()) {
        self.processor = processor
    }
    
    func processImage(_ data: Data) async throws -> Data {
        return try await processor.resizeImage(data, to: CGSize(width: 800, height: 600))
    }
}

class MediaCompressor: MediaCompressorProtocol {
    private let compressor: MediaCompressor
    
    init(compressor: MediaCompressor = MediaCompressor()) {
        self.compressor = compressor
    }
    
    func compressVideo(_ url: URL) async throws -> URL {
        return try await compressor.compressMedia(
            inputURL: url,
            presetName: .mediumQuality,
            originalResolution: CGSize(width: 1920, height: 1080),
            fileType: .mp4,
            outputFileType: .mp4
        )
    }
}
```

## Batch Processing

Process multiple items efficiently:

```swift
class BatchProcessor {
    func processBatch<T>(_ items: [T], operation: @escaping (T) async throws -> T) async throws -> [T] {
        return try await withThrowingTaskGroup(of: (Int, T).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let result = try await operation(item)
                    return (index, result)
                }
            }
            
            var results = Array(repeating: items[0], count: items.count)
            for try await (index, result) in group {
                results[index] = result
            }
            return results
        }
    }
}

// Usage
let processor = ImageProcessor()
let images = [image1Data, image2Data, image3Data]

let batchProcessor = BatchProcessor()
let processedImages = try await batchProcessor.processBatch(images) { imageData in
    try await processor.resizeImage(imageData, to: CGSize(width: 800, height: 600))
}
```

## Error Handling

Implement comprehensive error handling:

```swift
enum MediaProcessingError: Error {
    case compressionFailed(CompressionErrors)
    case imageProcessingFailed(ImageErrors)
    case invalidInput
    case timeout
}

class MediaProcessorWithErrorHandling {
    private let compressor = MediaCompressor()
    private let processor = ImageProcessor()
    
    func processWithRetry<T>(_ operation: @escaping () async throws -> T, maxRetries: Int = 3) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if attempt < maxRetries {
                    // Wait before retry
                    try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? MediaProcessingError.timeout
    }
    
    func compressVideo(_ url: URL) async throws -> URL {
        return try await processWithRetry {
            try await compressor.compressMedia(
                inputURL: url,
                presetName: .mediumQuality,
                originalResolution: CGSize(width: 1920, height: 1080),
                fileType: .mp4,
                outputFileType: .mp4
            )
        }
    }
}
```

## Configuration Management

Manage configuration for different environments:

```swift
struct MediaConfiguration {
    let maxConcurrentOperations: Int
    let memoryLimit: Int64
    let enableCompression: Bool
    let compressionQuality: Float
    
    static let development = MediaConfiguration(
        maxConcurrentOperations: 5,
        memoryLimit: 1024 * 1024 * 1024, // 1GB
        enableCompression: true,
        compressionQuality: 0.8
    )
    
    static let production = MediaConfiguration(
        maxConcurrentOperations: 10,
        memoryLimit: 2 * 1024 * 1024 * 1024, // 2GB
        enableCompression: true,
        compressionQuality: 0.9
    )
}

class ConfigurableMediaProcessor {
    private let configuration: MediaConfiguration
    private let compressor = MediaCompressor()
    private let processor = ImageProcessor()
    
    init(configuration: MediaConfiguration) {
        self.configuration = configuration
    }
    
    func processWithConfiguration(_ data: Data) async throws -> Data {
        // Apply configuration-based processing
        var processedData = data
        
        if configuration.enableCompression {
            // Apply compression based on configuration
            processedData = try await processor.resizeImage(
                processedData,
                to: CGSize(width: 800, height: 600),
                quality: .high
            )
        }
        
        return processedData
    }
}
```

## See Also

- [Getting Started](GettingStarted.md) - Quick start guide
- [API Reference](API_REFERENCE.md) - Complete API documentation
- [MediaCompressor](MediaCompressor.md) - Video compression API
- [ImageProcessor](ImageProcessor.md) - Image processing API 