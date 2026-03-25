//
//  UIImage+Extension.swift
//
//
//  Created by Cole M on 8/7/23.
//

#if os(iOS) && canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
import ImageIO

extension UIImage {
    
    public func roundCorners(withRadius radius: CGFloat) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        if
            let cgImage = self.cgImage,
            let context = CGContext(data: nil,
                                    width: Int(size.width),
                                    height: Int(size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: 4 * Int(size.width),
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
            context.beginPath()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.closePath()
            context.clip()
            context.draw(cgImage, in: rect)
            
            if let composedImage = context.makeImage() {
                return UIImage(cgImage: composedImage)
            }
        }
        
        return self
    }
    
    
    public func stripped(type: ImageType) throws -> UIImage {
        // Normalize to `.up` so dropping metadata does not rotate portrait captures.
        let normalizedImage: UIImage
        if self.imageOrientation == .up {
            normalizedImage = self
        } else {
            let renderer = UIGraphicsImageRenderer(size: self.size)
            normalizedImage = renderer.image { _ in
                self.draw(in: CGRect(origin: .zero, size: self.size))
            }
        }
        
        // Convert UIImage to Data (JPEG format)
        guard let imageData = type == .jpg ? normalizedImage.jpegData(compressionQuality: 1.0) : normalizedImage.pngData() else {
            throw ImageErrors.imageCreationFailed("Unable to convert UIImage to \(type == .jpg ? "JPEG" : "PNG") data.")
        }
        
        // Create a CGImageSource from the image data
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw ImageErrors.imageCreationFailed("Unable to create CGImageSource.")
        }
        
        // Create a mutable CFData object
        guard let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0) else {
            throw ImageErrors.imageCreationFailed("Unable to create mutable CFData.")
        }
        
        // Create a destination for the new image (no metadata)
        guard let destination = CGImageDestinationCreateWithData(mutableData, type == .jpg ? UTType.jpeg.identifier as CFString : UTType.png.identifier as CFString, 1, nil) else {
            throw ImageErrors.imageCreationFailed("Unable to create CGImageDestination.")
        }
        
        // Use thumbnail-with-transform so EXIF orientation is baked into pixels (portrait stays portrait).
        let maxPixelSize: Int = {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else {
                return 16384
            }
            return max(w, h)
        }()
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let orientedImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ImageErrors.imageCreationFailed("Unable to create orientation-normalized image from source.")
        }
        CGImageDestinationAddImage(destination, orientedImage, nil)
        if !CGImageDestinationFinalize(destination) {
            throw ImageErrors.imageCreationFailed("Failed to finalize the image destination.")
        }
        
        let jpegData = mutableData as Data
        
        // Create a new UIImage from the stripped data
        guard let strippedImage = UIImage(data: jpegData) else {
            throw ImageErrors.imageCreationFailed("Unable to create UIImage from stripped data.")
        }
        
        return strippedImage
    }
    
    /// Produces orientation-correct thumbnail JPEG data using ImageIO (no Metal/cgImage orientation loss).
    public func thumbnailJPEGData(maxSide: CGFloat, compressionQuality: CGFloat = 0.75) throws -> Data {
        guard let imageData = jpegData(compressionQuality: 1.0) else {
            throw ImageErrors.imageCreationFailed("Unable to get JPEG data for thumbnail.")
        }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw ImageErrors.imageCreationFailed("Unable to create CGImageSource for thumbnail.")
        }
        let maxPixelSize = Int(maxSide)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
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
