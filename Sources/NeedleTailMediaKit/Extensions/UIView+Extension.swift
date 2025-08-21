//
//  UIImage+Extension.swift
//
//
//  Created by Cole M on 8/7/23.
//

#if os(iOS) && canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

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
        // Convert UIImage to Data (JPEG format)
        guard let imageData = type == .jpg ? self.jpegData(compressionQuality: 1.0) : self.pngData() else {
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
        
        // Create a destination for the new image
        guard let destination = CGImageDestinationCreateWithData(mutableData, type == .jpg ? UTType.jpeg.identifier as CFString : UTType.png.identifier as CFString, 1, nil) else {
            throw ImageErrors.imageCreationFailed("Unable to create CGImageDestination.")
        }
        
        // Copy the image from the source to the destination without metadata
        if let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            if !CGImageDestinationFinalize(destination) {
                throw ImageErrors.imageCreationFailed("Failed to finalize the image destination.")
            }
        } else {
            throw ImageErrors.imageCreationFailed("Unable to create image from CGImageSource.")
        }
        
        // Convert CFData to Swift Data
        let jpegData = mutableData as Data
        
        // Create a new UIImage from the stripped data
        guard let strippedImage = UIImage(data: jpegData) else {
            throw ImageErrors.imageCreationFailed("Unable to create UIImage from stripped data.")
        }
        
        return strippedImage
    }
}
#endif
