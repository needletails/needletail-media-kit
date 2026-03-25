//
//  NSImage+Extension.swift
//  NeedleTail
//
//  Created by Cole M on 8/6/23.
//

public enum ImageType {
    case png, jpg
}

#if os(macOS) && canImport(Cocoa)
import Cocoa
import UniformTypeIdentifiers
import ImageIO

extension NSView {
    public func toImage() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        
        cacheDisplay(in: bounds, to: rep)
        let imageData = NSImage(size: rep.size)
        imageData.addRepresentation(rep)
        return imageData
    }
}

extension NSImage {
    public func resize(w: CGFloat, h: CGFloat) -> NSImage {
        let destSize = NSMakeSize(CGFloat(w), CGFloat(h))
        
        let imageRepresentation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(destSize.width),
            pixelsHigh: Int(destSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        
        imageRepresentation?.size = destSize
        NSGraphicsContext.saveGraphicsState()
        
        if let aRep = imageRepresentation {
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: aRep)
        }
        
        self.draw(
            in: NSMakeRect(0, 0, destSize.width, destSize.height),
            from: NSZeroRect,
            operation: NSCompositingOperation.copy,
            fraction: 1.0
        )
        
        NSGraphicsContext.restoreGraphicsState()
        
        let newImage = NSImage(size: destSize)
        if let aRep = imageRepresentation {
            newImage.addRepresentation(aRep)
        }
        
        return newImage
    }
    
    @MainActor public func merge(with other: NSImage?) -> NSImage? {
        guard let otherImage = other else {
            return nil
        }
        
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        let backgroundImageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        backgroundImageView.image = self
        
        let pixelImageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        pixelImageView.image = otherImage
        
        view.addSubview(backgroundImageView)
        view.addSubview(pixelImageView)
        
        return view.toImage()
    }
    
    public var cgImage: CGImage? {
        var imageRect = CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height)
        let imageRef = self.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
        return imageRef
    }
    
    public func maskWithGradient(start: NSColor, end: NSColor) -> NSImage? {
        let width = self.size.width
        let height = self.size.height
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        )
        
        guard let bitmapContext = context, let maskImage = self.cgImage else {
            return nil
        }
        
        let locations: [CGFloat] = [0.0, 1.0]
        let colors = [start.cgColor, end.cgColor] as CFArray
        let startPoint = CGPoint(x: width / 2, y: 0)
        let endPoint = CGPoint(x: width / 2, y: height)
        
        bitmapContext.clip(to: bounds, mask: maskImage)
        
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
            return nil
        }
        
        bitmapContext.drawLinearGradient(
            gradient,
            start: startPoint,
            end: endPoint,
            options: CGGradientDrawingOptions(rawValue: UInt32(0))
        )
        
        if let cgImage = bitmapContext.makeImage() {
            let coloredImage = NSImage(cgImage: cgImage, size: bounds.size)
            return coloredImage
        }
        
        return nil
    }
}

extension NSImage {
    public func pngData(
        size: CGSize,
        imageInterpolation: NSImageInterpolation = .high
    ) -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = imageInterpolation
        draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        
        return bitmap.representation(using: .png, properties: [:])
    }
    
    public func jpegData(
        maxSize: CGSize,
        imageInterpolation: NSImageInterpolation = .high
    ) -> Data? {
        // Get the original size
        let originalSize = self.size
        let aspectRatio = originalSize.width / originalSize.height
        
        // Calculate the new size while maintaining the aspect ratio
        var targetSize: CGSize
        if aspectRatio > 1 { // Landscape
            targetSize = CGSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        } else { // Portrait or square
            targetSize = CGSize(width: maxSize.height * aspectRatio, height: maxSize.height)
        }
        
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        
        bitmap.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = imageInterpolation
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        
        return bitmap.representation(using: .jpeg, properties: [:])
    }
    
    public func roundCorners(withRadius radius: CGFloat) -> NSImage {
        let rect = NSRect(origin: NSPoint.zero, size: size)
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
                return NSImage(cgImage: composedImage, size: size)
            }
        }
        
        return self
    }
    
    public func stripped(type: ImageType) throws -> NSImage {
        // Ensure we have TIFF representation
        guard let tiffData = self.tiffRepresentation else {
            throw ImageErrors.imageCreationFailed("No TIFF representation available.")
        }
        
        // Create a CGImageSource from the TIFF data
        guard let source = CGImageSourceCreateWithData(tiffData as CFData, nil) else {
            throw ImageErrors.imageCreationFailed("Unable to create CGImageSource.")
        }
        
        // Create a mutable CFData object
        guard let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0) else {
            throw ImageErrors.imageCreationFailed("Unable to create mutable CFData.")
        }
        
        // Create a destination for the output (no metadata)
        guard let destination = CGImageDestinationCreateWithData(mutableData, type == .png ? UTType.png.identifier as CFString : UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageErrors.imageCreationFailed("Unable to create CGImageDestination.")
        }
        
        // Create an orientation-normalized image so EXIF orientation is baked into pixels (matches UIImage.stripped behavior on iOS).
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
        
        let outputData = mutableData as Data
        guard let nsImage = NSImage(data: outputData) else {
            throw ImageErrors.imageCreationFailed("Unable to create NSImage from \(type == .png ? "PNG" : "JPG") data.")
        }
        
        return nsImage
    }
    
    /// Produces orientation-correct thumbnail JPEG data using ImageIO (no Metal/cgImage orientation loss).
    public func thumbnailJPEGData(maxSide: CGFloat, compressionQuality: CGFloat = 0.75) throws -> Data {
        guard let tiffData = tiffRepresentation else {
            throw ImageErrors.imageCreationFailed("No TIFF representation for thumbnail.")
        }
        guard let source = CGImageSourceCreateWithData(tiffData as CFData, nil) else {
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
