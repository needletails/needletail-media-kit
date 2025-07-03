#if os(macOS) || os(iOS)
//
//  ImageProcessor.swift
//  NeedleTailMediaKit
//
//  Created by Cole M on 5/12/23.
//

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Accelerate

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

/// A high-performance image processor for iOS and macOS applications.
/// Provides image resizing, filtering, and processing capabilities using Core Image and Accelerate frameworks.
@available(macOS 13.0, iOS 16.0, *)
public actor ImageProcessor {
    
    private let ciContext: CIContext
    
    public init() {
        self.ciContext = CIContext()
    }
    
    /// Resizes an image to the specified dimensions while maintaining aspect ratio
    /// - Parameters:
    ///   - image: The input image data
    ///   - targetSize: The desired output size
    ///   - quality: The interpolation quality (default: .high)
    /// - Returns: The resized image data
    /// - Throws: ImageErrors if processing fails
    public func resizeImage(
        _ image: Data,
        to targetSize: CGSize,
        quality: CGInterpolationQuality = .high
    ) async throws -> Data {
        guard let ciImage = CIImage(data: image) else {
            throw ImageErrors.invalidImageData
        }
        
        let scaleX = targetSize.width / ciImage.extent.width
        let scaleY = targetSize.height / ciImage.extent.height
        let scale = min(scaleX, scaleY)
        
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = ciImage.transformed(by: transform)
        
        guard let cgImage = ciContext.createCGImage(scaledImage, from: scaledImage.extent) else {
            throw ImageErrors.imageProcessingFailed("Failed to create CGImage from scaled image")
        }
        
        guard let imageData = cgImage.pngData() else {
            throw ImageErrors.imageProcessingFailed("Failed to convert CGImage to PNG data")
        }
        
        return imageData
    }
    
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
        guard let ciImage = CIImage(data: image) else {
            throw ImageErrors.invalidImageData
        }
        
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = ciImage
        blurFilter.radius = Float(radius)
        
        guard let outputImage = blurFilter.outputImage else {
            throw ImageErrors.imageProcessingFailed("Failed to apply blur filter")
        }
        
        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            throw ImageErrors.imageProcessingFailed("Failed to create CGImage from blurred image")
        }
        
        guard let imageData = cgImage.pngData() else {
            throw ImageErrors.imageProcessingFailed("Failed to convert CGImage to PNG data")
        }
        
        return imageData
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
        guard let ciImage = CIImage(data: image) else {
            throw ImageErrors.invalidImageData
        }
        
        let sepiaFilter = CIFilter.sepiaTone()
        sepiaFilter.inputImage = ciImage
        sepiaFilter.intensity = Float(intensity)
        
        guard let outputImage = sepiaFilter.outputImage else {
            throw ImageErrors.imageProcessingFailed("Failed to apply sepia filter")
        }
        
        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            throw ImageErrors.imageProcessingFailed("Failed to create CGImage from sepia image")
        }
        
        guard let imageData = cgImage.pngData() else {
            throw ImageErrors.imageProcessingFailed("Failed to convert CGImage to PNG data")
        }
        
        return imageData
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
        
        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            throw ImageErrors.imageProcessingFailed("Failed to create CGImage from adjusted image")
        }
        
        guard let imageData = cgImage.pngData() else {
            throw ImageErrors.imageProcessingFailed("Failed to convert CGImage to PNG data")
        }
        
        return imageData
    }
    
    /// Converts an image to grayscale using color controls
    /// - Parameter image: The input image data
    /// - Returns: The grayscale image data
    /// - Throws: ImageErrors if processing fails
    public func convertToGrayscale(_ image: Data) async throws -> Data {
        guard let ciImage = CIImage(data: image) else {
            throw ImageErrors.invalidImageData
        }
        
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciImage
        colorControls.saturation = 0.0
        
        guard let outputImage = colorControls.outputImage else {
            throw ImageErrors.imageProcessingFailed("Failed to apply grayscale filter")
        }
        
        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            throw ImageErrors.imageProcessingFailed("Failed to create CGImage from grayscale image")
        }
        
        guard let imageData = cgImage.pngData() else {
            throw ImageErrors.imageProcessingFailed("Failed to convert CGImage to PNG data")
        }
        
        return imageData
    }
}

// MARK: - CGImage Extension for PNG Data
private extension CGImage {
    func pngData() -> Data? {
        guard let dataProvider = dataProvider,
              let data = dataProvider.data else {
            return nil
        }
        return data as Data
    }
}
#endif
