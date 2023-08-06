#if os(macOS) || os(iOS)
//
//  ImageProcessor.swift
//  NeedleTail
//
//  Created by Cole M on 5/12/23.
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import Cocoa
#endif
import Accelerate
import Vision
import CoreImage.CIFilterBuiltins

public enum ImageErrors: Error {
    case imageError, cannotGetSize, cannotBlur
}


public class ImageProcessor {

    public static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    private static let pixelAttributes = [
        kCVPixelBufferIOSurfacePropertiesKey: [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCMSampleAttachmentKey_DisplayImmediately: true
        ]
    ] as? CFDictionary
    
#if os(iOS)
    public static func resize(_ imageData: Data, to desiredSize: CGSize, isThumbnail: Bool) async throws -> CGImage {
        guard let ciimage = CIImage(data: imageData) else { throw ImageErrors.imageError }
        guard let pb = await recreatePixelBuffer(from: ciimage) else { throw ImageErrors.imageError }
        guard let cgImage = try await createCGImage(from: pb, for: ciimage.extent.size, desiredSize: desiredSize, isThumbnail: isThumbnail) else { throw ImageErrors.imageError }
        return cgImage
    }
#elseif os(macOS)
    public static func resize(_ imageData: NSImage, to desiredSize: CGSize, isThumbnail: Bool) async throws -> NSImage {
        guard let cgImage = imageData.cgImage else { throw ImageErrors.imageError }
        let ciimage = CIImage(cgImage: cgImage)
        guard let pb = await recreatePixelBuffer(from: ciimage) else { throw ImageErrors.imageError }
        guard let newCGImage = try await createCGImage(from: pb, for: imageData.size, desiredSize: desiredSize, isThumbnail: isThumbnail) else { throw ImageErrors.imageError }
        return NSImage(cgImage: newCGImage, size: CGSize(width: newCGImage.width, height: newCGImage.height))
    }
#endif
    
    public static func recreatePixelBuffer(from image: CIImage) async -> CVPixelBuffer? {
            var pixelBuffer: CVPixelBuffer? = nil
            
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(image.extent.width),
                Int(image.extent.height),
                kCVPixelFormatType_32BGRA,
                pixelAttributes,
                &pixelBuffer
            )
            guard let pixelBuffer = pixelBuffer else { return nil }
            ciContext.render(image, to: pixelBuffer)
            return pixelBuffer
    }
    
    public static func createCGImage(
        from pixelBuffer: CVPixelBuffer,
        for size: CGSize,
        desiredSize: CGSize,
        isThumbnail: Bool
    ) async throws -> CGImage? {
        let newSize = await getNewSize(size: size, desiredSize: desiredSize, isThumbnail: isThumbnail)
        // Define the image format
        guard var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            renderingIntent: .defaultIntent
        ) else {
            throw vImage.Error.invalidImageFormat
        }
        var error: vImage_Error
        var sourceBuffer = vImage_Buffer()
        
        guard let inputCVImageFormat = vImageCVImageFormat.make(buffer: pixelBuffer) else { throw vImage.Error.invalidCVImageFormat }
        vImageCVImageFormat_SetColorSpace(inputCVImageFormat, CGColorSpaceCreateDeviceRGB())
        
        error = vImageBuffer_InitWithCVPixelBuffer(
            &sourceBuffer,
            &format,
            pixelBuffer,
            inputCVImageFormat,
            nil,
            vImage_Flags(kvImageNoFlags)
        )
        
        guard error == kvImageNoError else {
            throw vImage.Error(vImageError: error)
        }
        
        var destinationBuffer = try vImage_Buffer(width: Int(newSize.width), height: Int(newSize.height), bitsPerPixel: format.bitsPerPixel)
        // Scale the image
        error = vImageScale_ARGB8888(&sourceBuffer,
                                     &destinationBuffer,
                                     nil,
                                     vImage_Flags(kvImageHighQualityResampling))
        guard error == kvImageNoError else {
            throw vImage.Error(vImageError: error)
        }
        
        var resizedImage: CGImage?
        // Center the image
        resizedImage = try destinationBuffer.createCGImage(format: format)
        
        defer {
            sourceBuffer.free()
            destinationBuffer.free()
        }
        guard let resizedImage = resizedImage else { return nil }
        
        return resizedImage
    }
    
    public static func getAspectRatio(size: CGSize) -> CGFloat {
        if size.width > size.height {
            return size.width / size.height
        } else {
            return size.height / size.width
        }
    }
    
    @MainActor
    public static func getNewSize(size: CGSize, desiredSize: CGSize, isThumbnail: Bool = false) -> CGSize {
            let aspectRatio = getAspectRatio(size: size)
            if size.height > size.width {
                let height = desiredSize.width * aspectRatio
                if height > 250 && isThumbnail {
                    return CGSize(width: 250 / aspectRatio, height: 250)
                } else {
                    let width = desiredSize.height / aspectRatio
                    return CGSize(width: width, height: desiredSize.height)
                }
            } else {
                let width = desiredSize.height * aspectRatio
                #if os(iOS)
                if width > UIScreen.main.bounds.size.width {
                    let width = desiredSize.width
                    let height = desiredSize.width / aspectRatio
                    return CGSize(width: width, height: height)
                }                else if width > 250 && isThumbnail {
                    return CGSize(width: 250, height: 250 / aspectRatio)
                } else {
                    return CGSize(width: width, height: desiredSize.height)
                }
#elseif os(macOS)
                if width > NSApplication.shared.windows.first?.frame.width ?? 300{
                    let width = desiredSize.width
                    let height = desiredSize.width / aspectRatio
                    return CGSize(width: width, height: height)
                }                else if width > 250 && isThumbnail {
                    return CGSize(width: 250, height: 250 / aspectRatio)
                } else {
                    return CGSize(width: width, height: desiredSize.height)
                }
#endif
            }
    }
    
    
    public static func processImages(_
                                    pixelBuffer: CVPixelBuffer,
                                    backgroundBuffer: CVPixelBuffer
    ) async throws -> ImageObject? {
        // Create request handler
        let mask: VNPixelBufferObservation = try autoreleasepool {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: .up,
                                                options: [:])

            try handler.perform([request])

            guard let mask = request.results?.first else {
                throw ImageErrors.imageError
            }
            return mask
        }
        return try await blendImages(
            foregroundBuffer: pixelBuffer,
            maskedBuffer: mask.pixelBuffer,
            backgroundBuffer: backgroundBuffer
        )
    }
    
    public struct ImageObject: @unchecked Sendable {
        var buffer: CVPixelBuffer?
        var image: CIImage?
    }

    public static func blendImages(
        foregroundBuffer: CVPixelBuffer,
        maskedBuffer: CVPixelBuffer,
        backgroundBuffer: CVPixelBuffer
    ) async throws -> ImageObject? {

        guard let newForegroundBuffer = await recreatePixelBuffer(from: CIImage(cvPixelBuffer: foregroundBuffer)) else { return nil }
        guard let newMaskedBuffer = await recreatePixelBuffer(from: CIImage(cvPixelBuffer: maskedBuffer)) else { return nil }
        guard let newBackgroundBuffer = await recreatePixelBuffer(from: CIImage(cvPixelBuffer: backgroundBuffer)) else { return nil }

        let size = CGSize(
            width: newForegroundBuffer.width,
            height: newForegroundBuffer.height
        )
        
        guard let resizedMask = try await createCGImage(
            from: newMaskedBuffer,
            for: size,
            desiredSize: size,
            isThumbnail: false
        ) else { return nil }
        guard let resizedBackground = try await createCGImage(
            from: newBackgroundBuffer,
            for: size,
            desiredSize: size,
            isThumbnail: false
        ) else { return nil }
        guard let resizedForeground = try await createCGImage(
            from: newForegroundBuffer,
            for: size,
            desiredSize: size,
            isThumbnail: false
        ) else { return nil }
        
        let image: CIImage = autoreleasepool {
            let blendFilter = CIFilter.blendWithMask()
            blendFilter.inputImage = CIImage(cgImage: resizedForeground)
            blendFilter.backgroundImage = CIImage(cgImage: resizedBackground)
            blendFilter.maskImage = CIImage(cgImage: resizedMask)

            let image = blendFilter.outputImage
            return image!
        }
        //        create pixel buffer
        let buffer = await recreatePixelBuffer(from: image)
        return ImageObject(buffer: buffer, image: image)
        
    }
    
#if os(iOS)
    public static func fillParent(with aspectRatio: CGFloat, from imageData: UIImage) -> CGSize {
            if imageData.size.height > imageData.size.width {
                let width = UIScreen.main.bounds.size.width
                let height = UIScreen.main.bounds.size.width * aspectRatio
                return CGSize(width: width, height: height)
            } else {
                let width = UIScreen.main.bounds.size.width
                let height = UIScreen.main.bounds.size.width / aspectRatio
                return CGSize(width: width, height: height)
            }
    }
#else
    public static func fillParent(with aspectRatio: CGFloat, from imageData: NSImage) -> CGSize {
        guard let frame = NSScreen.main?.frame else { return CGSize() }
        if imageData.size.height > imageData.size.width {
            let width = frame.width
            let height = frame.width * aspectRatio
            return CGSize(width: width, height: height)
        } else {
            let width = frame.width
            let height = frame.width / aspectRatio
            return CGSize(width: width, height: height)
        }
    }
#endif
}

#if os(iOS)
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
}

#else
extension NSImage {
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

    var cgImage: CGImage? {
        var rect = CGRect.init(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
#endif


@discardableResult private func asyncDispatch<T>(_ block: @escaping () -> T) -> T {
    let queue = DispatchQueue.main
    let group = DispatchGroup()
    var result: T?
    group.enter()
    queue.async(group: group) { result = block(); group.leave(); }
    group.wait()
    
    return result!
}
#endif
