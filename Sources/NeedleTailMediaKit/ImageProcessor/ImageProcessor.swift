//
//  ImageProcessor.swift
//  NeedleTailMediaKit
//
//  Created by Cole M on 5/12/23.
//

import Foundation
#if canImport(Accelerate) && canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import CoreImage
import CoreImage.CIFilterBuiltins
import Accelerate
import ImageIO
import UniformTypeIdentifiers
#endif

public enum ImageErrors: Error, LocalizedError, Sendable {
    case imageCreationFailed(String)
    case imageProcessingFailed(String)
    case invalidImageData
    case unsupportedImageFormat
    
    public var errorDescription: String? {
        switch self {
        case .imageCreationFailed(let message):
            return message
        case .imageProcessingFailed(let message):
            return message
        case .invalidImageData:
            return "invalid image data"
        case .unsupportedImageFormat:
            return "unsupported image format"
        }
    }
}

/// A high-performance cross-platform image processor.
/// Provides image resizing, filtering, and processing capabilities.
/// On Apple platforms, uses Core Image and Accelerate frameworks.
/// On Android, uses Android Bitmap APIs (transpiled via Skip Swift).
@available(macOS 13.0, iOS 16.0, *)
public actor ImageProcessor {
    
    #if canImport(Accelerate) && canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    private let ciContext: CIContext
    private let outputColorSpace = CGColorSpaceCreateDeviceRGB()
    #endif
    
    #if SKIP || os(Android)
    private let androidProcessor: AndroidImageProcessor
    #endif
    
    public init() {
        #if canImport(Accelerate) && canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        // Favor GPU rendering and reduce intermediate caching for lower memory churn.
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
        #endif
        #if SKIP || os(Android)
        self.androidProcessor = AndroidImageProcessor()
        #endif
    }

    #if canImport(Accelerate) && canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    private func pngData(from image: CIImage) throws -> Data {
        // Avoid CI->CGImage->ImageIO hops; this is typically faster and reduces peak memory.
        if let data = ciContext.pngRepresentation(
            of: image,
            format: .RGBA8,
            colorSpace: outputColorSpace,
            options: [:]
        ) {
            return data
        }
        throw ImageErrors.imageProcessingFailed("Failed to encode CIImage to PNG data")
    }
    #endif

    #if SKIP || os(Android)
    private nonisolated func mapAndroidError(_ error: AndroidImageProcessor.ImageErrors) -> ImageErrors {
        switch error {
        case .imageCreationFailed(let message):
            return .imageCreationFailed(message)
        case .imageProcessingFailed(let message):
            return .imageProcessingFailed(message)
        case .invalidImageData:
            return .invalidImageData
        case .unsupportedImageFormat:
            return .unsupportedImageFormat
        }
    }
    #endif
    
    /// Resizes an image to the specified dimensions while maintaining aspect ratio
    /// - Parameters:
    ///   - image: The input image data
    ///   - targetSize: The desired output size
    ///   - quality: The interpolation quality (default: .high on Apple, 2 on Android)
    /// - Returns: The resized image data
    /// - Throws: ImageErrors if processing fails
    #if !SKIP && !os(Android) && !os(Linux)
    public func resizeImage(
        _ image: Data,
        to targetSize: CGSize,
        quality: CGInterpolationQuality = .high
    ) async throws -> Data {
        #if canImport(Accelerate) && canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        // Use Apple implementation
        guard let ciImage = CIImage(data: image) else {
            throw ImageErrors.invalidImageData
        }
        
        let scaleX = targetSize.width / ciImage.extent.width
        let scaleY = targetSize.height / ciImage.extent.height
        let scale = min(scaleX, scaleY)
        
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = ciImage.transformed(by: transform)

        return try pngData(from: scaledImage)
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
    #else
    public func resizeImage(
        _ image: Data,
        to targetSize: CGSize,
        quality: Int = 2
    ) async throws -> Data {
        #if SKIP || os(Android)
        // Call into SKIP-transpiled Android implementation
        // When SKIP transpiles, this block is included in the Kotlin code
        do {
            return try await androidProcessor.resizeImage(image, to: targetSize, quality: quality)
        } catch let error as AndroidImageProcessor.ImageErrors {
            throw mapAndroidError(error)
        }
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
    #endif
    
    /// Applies a blur effect to an image
    /// - Parameters:
    ///   - image: The input image data
    ///   - radius: The blur radius (default: 10.0)
    /// - Returns: The blurred image data
    /// - Throws: ImageErrors if processing fails
    public func applyBlur(
        to image: Data,
        radius: Double = 10.0
    ) async throws -> Data {
        #if SKIP || os(Android)
        // Call into SKIP-transpiled Android implementation
        do {
            return try await androidProcessor.applyBlur(to: image, radius: radius)
        } catch let error as AndroidImageProcessor.ImageErrors {
            throw mapAndroidError(error)
        }
        #elseif canImport(Accelerate) && canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        // Use Apple implementation
        guard let ciImage = CIImage(data: image) else {
            throw ImageErrors.invalidImageData
        }
        
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = ciImage
        blurFilter.radius = Float(radius)
        
        guard let outputImage = blurFilter.outputImage else {
            throw ImageErrors.imageProcessingFailed("Failed to apply blur filter")
        }

        // Gaussian blur can expand extent; crop back to input size to keep output dimensions stable.
        return try pngData(from: outputImage.cropped(to: ciImage.extent))
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
    
    /// Applies a sepia tone effect to an image
    /// - Parameters:
    ///   - image: The input image data
    ///   - intensity: The sepia intensity (0.0 to 1.0, default: 0.8)
    /// - Returns: The sepia-toned image data
    /// - Throws: ImageErrors if processing fails
    public func applySepia(
        to image: Data,
        intensity: Double = 0.8
    ) async throws -> Data {
        #if SKIP || os(Android)
        // Call into SKIP-transpiled Android implementation
        do {
            return try await androidProcessor.applySepia(to: image, intensity: intensity)
        } catch let error as AndroidImageProcessor.ImageErrors {
            throw mapAndroidError(error)
        }
        #elseif canImport(Accelerate) && canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        // Use Apple implementation
        guard let ciImage = CIImage(data: image) else {
            throw ImageErrors.invalidImageData
        }
        
        let sepiaFilter = CIFilter.sepiaTone()
        sepiaFilter.inputImage = ciImage
        sepiaFilter.intensity = Float(intensity)
        
        guard let outputImage = sepiaFilter.outputImage else {
            throw ImageErrors.imageProcessingFailed("Failed to apply sepia filter")
        }

        return try pngData(from: outputImage)
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
    
    /// Adjusts the brightness and contrast of an image
    /// - Parameters:
    ///   - image: The input image data
    ///   - brightness: Brightness adjustment (-1.0 to 1.0, default: 0.0)
    ///   - contrast: Contrast adjustment (0.0 to 4.0, default: 1.0)
    /// - Returns: The adjusted image data
    /// - Throws: ImageErrors if processing fails
    public func adjustBrightnessContrast(
        image: Data,
        brightness: Double = 0.0,
        contrast: Double = 1.0
    ) async throws -> Data {
        #if SKIP || os(Android)
        // Call into SKIP-transpiled Android implementation
        do {
            return try await androidProcessor.adjustBrightnessContrast(image: image, brightness: brightness, contrast: contrast)
        } catch let error as AndroidImageProcessor.ImageErrors {
            throw mapAndroidError(error)
        }
        #elseif canImport(Accelerate) && canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        // Use Apple implementation
        guard let ciImage = CIImage(data: image) else {
            throw ImageErrors.invalidImageData
        }
        
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciImage
        colorControls.brightness = Float(brightness)
        colorControls.contrast = Float(contrast)
        
        guard let outputImage = colorControls.outputImage else {
            throw ImageErrors.imageProcessingFailed("Failed to apply brightness/contrast adjustment")
        }

        return try pngData(from: outputImage)
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
    
    /// Converts an image to grayscale using color controls
    /// - Parameter image: The input image data
    /// - Returns: The grayscale image data
    /// - Throws: ImageErrors if processing fails
    public func convertToGrayscale(_ image: Data) async throws -> Data {
        #if SKIP || os(Android)
        // Call into SKIP-transpiled Android implementation
        do {
            return try await androidProcessor.convertToGrayscale(image)
        } catch let error as AndroidImageProcessor.ImageErrors {
            throw mapAndroidError(error)
        }
        #elseif canImport(Accelerate) && canImport(CoreImage) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        // Use Apple implementation
        guard let ciImage = CIImage(data: image) else {
            throw ImageErrors.invalidImageData
        }
        
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciImage
        colorControls.saturation = 0.0
        
        guard let outputImage = colorControls.outputImage else {
            throw ImageErrors.imageProcessingFailed("Failed to apply grayscale filter")
        }

        return try pngData(from: outputImage)
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
}
