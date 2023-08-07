//
//  NSImage+Extension.swift
//  NeedleTail
//
//  Created by Cole M on 8/6/23.
//

#if os(macOS)
import Cocoa

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
    
    public func merge(with other: NSImage?) -> NSImage? {
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
        
        if let cImage = bitmapContext.makeImage() {
            let coloredImage = NSImage(cgImage: cImage, size: bounds.size)
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
        
        return bitmap.representation(using: .jpeg, properties: [:])
    }
}

extension NSImage: @unchecked Sendable {}
#endif
