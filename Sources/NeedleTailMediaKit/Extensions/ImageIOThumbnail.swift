//
//  ImageIOThumbnail.swift
//  NeedleTailMediaKit
//

#if (os(iOS) || os(macOS)) && canImport(ImageIO)
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Orientation-correct thumbnail JPEG via ImageIO (no Metal/cgImage orientation loss).
public enum ImageIOThumbnail {
    /// Creates JPEG data for a thumbnail with EXIF orientation baked in.
    /// - Parameters:
    ///   - imageData: Source image data (JPEG, PNG, or TIFF).
    ///   - maxSide: Longest side of the thumbnail in pixels.
    ///   - compressionQuality: JPEG quality 0...1.
    /// - Returns: Thumbnail JPEG data.
    public static func createOrientedJPEG(
        imageData: Data,
        maxSide: Int,
        compressionQuality: CGFloat
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw ImageErrors.imageCreationFailed("Unable to create CGImageSource for thumbnail.")
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ImageErrors.imageCreationFailed("Unable to create thumbnail with transform.")
        }
        guard let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0) else {
            throw ImageErrors.imageCreationFailed("Unable to create mutable data.")
        }
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageErrors.imageCreationFailed("Unable to create JPEG destination.")
        }
        let destOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: compressionQuality]
        CGImageDestinationAddImage(destination, thumbnail, destOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageErrors.imageCreationFailed("Failed to finalize thumbnail JPEG.")
        }
        return mutableData as Data
    }
}
#endif
