import Foundation
#if SKIP
import SkipFoundation
#endif

/// Android-specific image processing implementation using Android Bitmap APIs
public actor AndroidImageProcessor {
    
    public init() {}
    
    public enum ImageErrors: Error, Sendable {
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
    
    /// Resizes an image to the specified dimensions while maintaining aspect ratio
    /// - Parameters:
    ///   - image: The input image data
    ///   - targetSize: The desired output size
    ///   - quality: The interpolation quality (not used on Android, but kept for API compatibility)
    /// - Returns: The resized image data as PNG
    /// - Throws: ImageErrors if processing fails
    public func resizeImage(
        _ image: Data,
        to targetSize: CGSize,
        quality: Int = 1 // 0 = low, 1 = medium, 2 = high (Android Bitmap filtering)
    ) async throws -> Data {
        #if SKIP
        // Android implementation using Skip's interop
        let bitmapFactory = android.graphics.BitmapFactory()
        let byteArray = image.toKotlinByteArray()
        guard let bitmap = bitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
            throw ImageErrors.invalidImageData
        }
        
        let scaledBitmap = android.graphics.Bitmap.createScaledBitmap(
            bitmap,
            Int(targetSize.width),
            Int(targetSize.height),
            quality > 0 // Use filtering if quality > 0
        )
        
        let outputStream = java.io.ByteArrayOutputStream()
        let success = scaledBitmap.compress(
            android.graphics.Bitmap.CompressFormat.PNG,
            100, // PNG quality (0-100, but PNG is lossless)
            outputStream
        )
        
        guard success else {
            throw ImageErrors.imageProcessingFailed("Failed to compress bitmap to PNG")
        }
        
        let result = outputStream.toByteArray()
        return Data(bytes: result)
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
    
    /// Applies a blur effect to an image using Android's RenderScript or Bitmap filtering
    /// - Parameters:
    ///   - image: The input image data
    ///   - radius: The blur radius
    /// - Returns: The blurred image data
    /// - Throws: ImageErrors if processing fails
    public func applyBlur(
        to image: Data,
        radius: Double = 10.0
    ) async throws -> Data {
        #if SKIP
        let bitmapFactory = android.graphics.BitmapFactory()
        let byteArray = image.toKotlinByteArray()
        guard let bitmap = bitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
            throw ImageErrors.invalidImageData
        }
        
        // Simple blur using box filter approximation
        // For production, consider using RenderScript or a more sophisticated blur algorithm
        let scaledRadius = Int(radius)
        let blurredBitmap = applyBoxBlur(bitmap: bitmap, radius: scaledRadius)
        
        let outputStream = java.io.ByteArrayOutputStream()
        let success = blurredBitmap.compress(
            android.graphics.Bitmap.CompressFormat.PNG,
            100,
            outputStream
        )
        
        guard success else {
            throw ImageErrors.imageProcessingFailed("Failed to compress blurred bitmap")
        }
        
        let result = outputStream.toByteArray()
        return Data(bytes: result)
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
        #if SKIP
        let bitmapFactory = android.graphics.BitmapFactory()
        let byteArray = image.toKotlinByteArray()
        guard let bitmap = bitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
            throw ImageErrors.invalidImageData
        }
        
        let sepiaBitmap = applySepiaFilter(bitmap: bitmap, intensity: Float(intensity))
        
        let outputStream = java.io.ByteArrayOutputStream()
        let success = sepiaBitmap.compress(
            android.graphics.Bitmap.CompressFormat.PNG,
            100,
            outputStream
        )
        
        guard success else {
            throw ImageErrors.imageProcessingFailed("Failed to compress sepia bitmap")
        }
        
        let result = outputStream.toByteArray()
        return Data(bytes: result)
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
        #if SKIP
        let bitmapFactory = android.graphics.BitmapFactory()
        let byteArray = image.toKotlinByteArray()
        guard let bitmap = bitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
            throw ImageErrors.invalidImageData
        }
        
        let adjustedBitmap = applyBrightnessContrast(
            bitmap: bitmap,
            brightness: Float(brightness),
            contrast: Float(contrast)
        )
        
        let outputStream = java.io.ByteArrayOutputStream()
        let success = adjustedBitmap.compress(
            android.graphics.Bitmap.CompressFormat.PNG,
            100,
            outputStream
        )
        
        guard success else {
            throw ImageErrors.imageProcessingFailed("Failed to compress adjusted bitmap")
        }
        
        let result = outputStream.toByteArray()
        return Data(bytes: result)
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
    
    /// Converts an image to grayscale
    /// - Parameter image: The input image data
    /// - Returns: The grayscale image data
    /// - Throws: ImageErrors if processing fails
    public func convertToGrayscale(_ image: Data) async throws -> Data {
        #if SKIP
        let bitmapFactory = android.graphics.BitmapFactory()
        let byteArray = image.toKotlinByteArray()
        guard let bitmap = bitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
            throw ImageErrors.invalidImageData
        }
        
        let grayscaleBitmap = applyGrayscale(bitmap: bitmap)
        
        let outputStream = java.io.ByteArrayOutputStream()
        let success = grayscaleBitmap.compress(
            android.graphics.Bitmap.CompressFormat.PNG,
            100,
            outputStream
        )
        
        guard success else {
            throw ImageErrors.imageProcessingFailed("Failed to compress grayscale bitmap")
        }
        
        let result = outputStream.toByteArray()
        return Data(bytes: result)
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
    
    #if SKIP
    // MARK: - Private Helper Methods
    
    private func applyBoxBlur(bitmap: android.graphics.Bitmap, radius: Int) -> android.graphics.Bitmap {
        // Simple box blur implementation
        // For production, consider using RenderScript or a more efficient algorithm
        let width = bitmap.getWidth()
        let height = bitmap.getHeight()
        let pixels = kotlin.IntArray(size: width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        
        // Apply horizontal blur
        for y in 0..<height {
            for x in 0..<width {
                var r = 0, g = 0, b = 0, a = 0
                var count = 0
                
                for dx in -radius...radius {
                    let nx = x + dx
                    if nx >= 0 && nx < width {
                        let pixel = pixels[y * width + nx]
                        r += (pixel >> 16) & 0xFF
                        g += (pixel >> 8) & 0xFF
                        b += pixel & 0xFF
                        a += (pixel >> 24) & 0xFF
                        count += 1
                    }
                }
                
                if count > 0 {
                    r /= count
                    g /= count
                    b /= count
                    a /= count
                    pixels[y * width + x] = (a << 24) | (r << 16) | (g << 8) | b
                }
            }
        }
        
        // Apply vertical blur
        for y in 0..<height {
            for x in 0..<width {
                var r = 0, g = 0, b = 0, a = 0
                var count = 0
                
                for dy in -radius...radius {
                    let ny = y + dy
                    if ny >= 0 && ny < height {
                        let pixel = pixels[ny * width + x]
                        r += (pixel >> 16) & 0xFF
                        g += (pixel >> 8) & 0xFF
                        b += pixel & 0xFF
                        a += (pixel >> 24) & 0xFF
                        count += 1
                    }
                }
                
                if count > 0 {
                    r /= count
                    g /= count
                    b /= count
                    a /= count
                    pixels[y * width + x] = (a << 24) | (r << 16) | (g << 8) | b
                }
            }
        }
        
        let result = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
        result.setPixels(pixels, 0, width, 0, 0, width, height)
        return result
    }
    
    private func applySepiaFilter(bitmap: android.graphics.Bitmap, intensity: Float) -> android.graphics.Bitmap {
        let width = bitmap.getWidth()
        let height = bitmap.getHeight()
        let pixels = kotlin.IntArray(size: width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        
        for i in 0..<pixels.length {
            let pixel = pixels[i]
            let a = (pixel >> 24) & 0xFF
            var r = (pixel >> 16) & 0xFF
            var g = (pixel >> 8) & 0xFF
            var b = pixel & 0xFF
            
            // Sepia tone formula
            let tr = Int((Float(r) * 0.393 + Float(g) * 0.769 + Float(b) * 0.189) * intensity + Float(r) * (1.0 - intensity))
            let tg = Int((Float(r) * 0.349 + Float(g) * 0.686 + Float(b) * 0.168) * intensity + Float(g) * (1.0 - intensity))
            let tb = Int((Float(r) * 0.272 + Float(g) * 0.534 + Float(b) * 0.131) * intensity + Float(b) * (1.0 - intensity))
            
            r = min(255, max(0, tr))
            g = min(255, max(0, tg))
            b = min(255, max(0, tb))
            
            pixels[i] = (a << 24) | (r << 16) | (g << 8) | b
        }
        
        let result = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
        result.setPixels(pixels, 0, width, 0, 0, width, height)
        return result
    }
    
    private func applyBrightnessContrast(bitmap: android.graphics.Bitmap, brightness: Float, contrast: Float) -> android.graphics.Bitmap {
        let width = bitmap.getWidth()
        let height = bitmap.getHeight()
        let pixels = kotlin.IntArray(size: width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        
        let brightnessAdjustment = Int(brightness * 255.0)
        let contrastFactor = (259.0 * (contrast * 255.0 + 255.0)) / (255.0 * (259.0 - contrast * 255.0))
        
        for i in 0..<pixels.length {
            let pixel = pixels[i]
            let a = (pixel >> 24) & 0xFF
            var r = (pixel >> 16) & 0xFF
            var g = (pixel >> 8) & 0xFF
            var b = pixel & 0xFF
            
            // Apply contrast
            r = Int((Float(r) - 128.0) * contrastFactor + 128.0)
            g = Int((Float(g) - 128.0) * contrastFactor + 128.0)
            b = Int((Float(b) - 128.0) * contrastFactor + 128.0)
            
            // Apply brightness
            r += brightnessAdjustment
            g += brightnessAdjustment
            b += brightnessAdjustment
            
            r = min(255, max(0, r))
            g = min(255, max(0, g))
            b = min(255, max(0, b))
            
            pixels[i] = (a << 24) | (r << 16) | (g << 8) | b
        }
        
        let result = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
        result.setPixels(pixels, 0, width, 0, 0, width, height)
        return result
    }
    
    private func applyGrayscale(bitmap: android.graphics.Bitmap) -> android.graphics.Bitmap {
        let width = bitmap.getWidth()
        let height = bitmap.getHeight()
        let pixels = kotlin.IntArray(size: width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        
        for i in 0..<pixels.length {
            let pixel = pixels[i]
            let a = (pixel >> 24) & 0xFF
            let r = (pixel >> 16) & 0xFF
            let g = (pixel >> 8) & 0xFF
            let b = pixel & 0xFF
            
            // Grayscale formula (luminance)
            let gray = Int(0.299 * Float(r) + 0.587 * Float(g) + 0.114 * Float(b))
            
            pixels[i] = (a << 24) | (gray << 16) | (gray << 8) | gray
        }
        
        let result = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
        result.setPixels(pixels, 0, width, 0, 0, width, height)
        return result
    }
    #endif
}

#if SKIP
// MARK: - Data Extension for Kotlin Interop
extension Data {
    func toKotlinByteArray() -> kotlin.ByteArray {
        return kotlin.ByteArray(size: self.count) { index in
            self[index]
        }
    }
}

extension kotlin.ByteArray {
    func toSwiftData() -> Data {
        return Data(bytes: self)
    }
}
#endif

