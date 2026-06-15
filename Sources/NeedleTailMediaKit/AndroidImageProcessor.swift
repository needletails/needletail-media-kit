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
        let byteArray = image.platformValue
        guard let bitmap = android.graphics.BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
            throw ImageErrors.invalidImageData
        }
        
        let originalWidth = bitmap.getWidth()
        let originalHeight = bitmap.getHeight()
        guard originalWidth > 0, originalHeight > 0 else {
            throw ImageErrors.invalidImageData
        }

        let targetWidth = max(1, Int(targetSize.width))
        let targetHeight = max(1, Int(targetSize.height))
        let widthScale = Double(targetWidth) / Double(originalWidth)
        let heightScale = Double(targetHeight) / Double(originalHeight)
        let scale = min(widthScale, heightScale)
        let outputWidth = max(1, Int(Double(originalWidth) * scale))
        let outputHeight = max(1, Int(Double(originalHeight) * scale))

        let scaledBitmap = android.graphics.Bitmap.createScaledBitmap(
            bitmap,
            outputWidth,
            outputHeight,
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
        return Data(platformValue: result)
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
        let byteArray = image.platformValue
        guard let bitmap = android.graphics.BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
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
        return Data(platformValue: result)
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
        let byteArray = image.platformValue
        guard let bitmap = android.graphics.BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
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
        return Data(platformValue: result)
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
        let byteArray = image.platformValue
        guard let bitmap = android.graphics.BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
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
        return Data(platformValue: result)
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
        let byteArray = image.platformValue
        guard let bitmap = android.graphics.BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
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
        return Data(platformValue: result)
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }
    
    /// Returns the longest edge length in pixels, or nil when the payload cannot be decoded.
    public static func longestSide(from imageData: Data) -> Int? {
        #if SKIP
        let options = android.graphics.BitmapFactory.Options()
        options.inJustDecodeBounds = true
        let bytes = imageData.platformValue
        guard bytes.size > 0 else { return nil }
        _ = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        let w = max(options.outWidth, 1)
        let h = max(options.outHeight, 1)
        return max(w, h)
        #else
        return nil
        #endif
    }

    /// Decodes, optionally scales, and re-encodes JPEG without relying on EXIF stripping.
    public static func reencodeJPEG(
        imageData: Data,
        maxSide: Int,
        compressionQuality: CGFloat
    ) throws -> Data {
        #if SKIP
        let byteArray = imageData.platformValue
        guard byteArray.size > 0 else {
            throw ImageErrors.invalidImageData
        }
        guard let bitmap = android.graphics.BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
            throw ImageErrors.invalidImageData
        }
        return try encodeScaledJPEG(from: bitmap, maxSide: maxSide, compressionQuality: compressionQuality)
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }

    /// Preferred upload path: orientation-correct JPEG with EXIF stripped when possible.
    public static func makeUploadJPEG(
        imageData: Data,
        maxSide: Int,
        compressionQuality: CGFloat
    ) throws -> Data {
        do {
            return try makeOrientationCorrectThumbnailJPEG(
                imageData: imageData,
                maxSide: maxSide,
                compressionQuality: compressionQuality
            )
        } catch {
            return try reencodeJPEG(
                imageData: imageData,
                maxSide: maxSide,
                compressionQuality: compressionQuality
            )
        }
    }

    /// Produces an orientation-correct thumbnail JPEG from image data (Android/Skip).
    /// Reads EXIF orientation, applies rotation via Matrix, scales longest side to `maxSide`, compresses to JPEG.
    /// - Parameters:
    ///   - imageData: Source image bytes (JPEG, PNG, WebP, etc.).
    ///   - maxSide: Longest side of the thumbnail in pixels.
    ///   - compressionQuality: JPEG quality in 0...1.
    /// - Returns: Thumbnail JPEG data.
    public static func makeOrientationCorrectThumbnailJPEG(imageData: Data, maxSide: Int, compressionQuality: CGFloat) throws -> Data {
        #if SKIP
        let byteArray = imageData.platformValue
        guard byteArray.size > 0 else {
            throw ImageErrors.invalidImageData
        }

        let orientation = readEXIFOrientation(from: byteArray)
        guard let bitmap = android.graphics.BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size) else {
            throw ImageErrors.invalidImageData
        }

        let orientedBitmap = applyOrientation(to: bitmap, orientation: orientation)
        return try encodeScaledJPEG(
            from: orientedBitmap,
            maxSide: maxSide,
            compressionQuality: compressionQuality
        )
        #else
        throw ImageErrors.unsupportedImageFormat
        #endif
    }

    #if SKIP
    private static func readEXIFOrientation(from byteArray: kotlin.ByteArray) -> Int {
        do {
            let inputStream = java.io.ByteArrayInputStream(byteArray)
            let exif = android.media.ExifInterface(inputStream)
            return exif.getAttributeInt(
                android.media.ExifInterface.TAG_ORIENTATION,
                android.media.ExifInterface.ORIENTATION_NORMAL
            )
        } catch {
            return android.media.ExifInterface.ORIENTATION_NORMAL
        }
    }

    private static func applyOrientation(to bitmap: android.graphics.Bitmap, orientation: Int) -> android.graphics.Bitmap {
        let degrees: Int
        switch orientation {
        case android.media.ExifInterface.ORIENTATION_ROTATE_90: degrees = 90
        case android.media.ExifInterface.ORIENTATION_ROTATE_180: degrees = 180
        case android.media.ExifInterface.ORIENTATION_ROTATE_270: degrees = 270
        default: degrees = 0
        }
        guard degrees != 0 else { return bitmap }
        let matrix = android.graphics.Matrix()
        matrix.postRotate(Float(degrees))
        return android.graphics.Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.getWidth(),
            bitmap.getHeight(),
            matrix,
            true
        )
    }

    private static func encodeScaledJPEG(
        from sourceBitmap: android.graphics.Bitmap,
        maxSide: Int,
        compressionQuality: CGFloat
    ) throws -> Data {
        let w = sourceBitmap.getWidth()
        let h = sourceBitmap.getHeight()
        guard w > 0, h > 0 else {
            throw ImageErrors.invalidImageData
        }

        let boundedMaxSide = max(maxSide, 1)
        let longest = max(w, h)
        let outW: Int
        let outH: Int
        if longest <= boundedMaxSide || boundedMaxSide >= 16_384 {
            outW = w
            outH = h
        } else {
            outW = max(1, w * boundedMaxSide / longest)
            outH = max(1, h * boundedMaxSide / longest)
        }

        let scaledBitmap = if outW == w && outH == h {
            sourceBitmap
        } else {
            android.graphics.Bitmap.createScaledBitmap(sourceBitmap, outW, outH, true)
        }

        let outputStream = java.io.ByteArrayOutputStream()
        let quality = Int(Swift.max(0.0, Swift.min(compressionQuality, 1.0)) * 100.0)
        let success = scaledBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, quality, outputStream)
        guard success else {
            throw ImageErrors.imageProcessingFailed("Failed to compress thumbnail to JPEG")
        }
        let result = outputStream.toByteArray()
        guard result.size > 0 else {
            throw ImageErrors.imageProcessingFailed("JPEG encoder returned empty payload")
        }
        return Data(platformValue: result)
    }
    #endif
    
        #if SKIP
    // MARK: - Private Helper Methods
    
    private func applyBoxBlur(bitmap: android.graphics.Bitmap, radius: Int) -> android.graphics.Bitmap {
        // Box blur implementation.
        // Optimized to O(width*height) via sliding-window sums while preserving the
        // exact edge handling and integer averaging of the original implementation.
        let width = bitmap.getWidth()
        let height = bitmap.getHeight()
        if radius <= 0 || width <= 0 || height <= 0 {
            return bitmap
        }
        let pixels = kotlin.IntArray(size: width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        
        // Horizontal pass into temp
        let temp = kotlin.IntArray(size: width * height)
        for y in 0..<height {
            let rowBase = y * width
            var sumA = 0
            var sumR = 0
            var sumG = 0
            var sumB = 0
            var count = 0
            
            // Initialize window for x=0: [0 ... min(radius, width-1)]
            let rightInit = min(radius, width - 1)
            for nx in 0...rightInit {
                let p = pixels[rowBase + nx]
                sumA += (p >> 24) & 0xFF
                sumR += (p >> 16) & 0xFF
                sumG += (p >> 8) & 0xFF
                sumB += p & 0xFF
                count += 1
            }
            
            // x=0
            var a = sumA / count
            var r = sumR / count
            var g = sumG / count
            var b = sumB / count
            temp[rowBase + 0] = (a << 24) | (r << 16) | (g << 8) | b
            
            if width == 1 { continue }
            
            // Slide window across row
            for x in 1..<width {
                let outX = x - radius - 1
                if outX >= 0 {
                    let pOut = pixels[rowBase + outX]
                    sumA -= (pOut >> 24) & 0xFF
                    sumR -= (pOut >> 16) & 0xFF
                    sumG -= (pOut >> 8) & 0xFF
                    sumB -= pOut & 0xFF
                    count -= 1
                }
                let inX = x + radius
                if inX < width {
                    let pIn = pixels[rowBase + inX]
                    sumA += (pIn >> 24) & 0xFF
                    sumR += (pIn >> 16) & 0xFF
                    sumG += (pIn >> 8) & 0xFF
                    sumB += pIn & 0xFF
                    count += 1
                }
                a = sumA / count
                r = sumR / count
                g = sumG / count
                b = sumB / count
                temp[rowBase + x] = (a << 24) | (r << 16) | (g << 8) | b
            }
        }
        
        // Vertical pass back into pixels
        for x in 0..<width {
            var sumA = 0
            var sumR = 0
            var sumG = 0
            var sumB = 0
            var count = 0
            
            // Initialize window for y=0: [0 ... min(radius, height-1)]
            let bottomInit = min(radius, height - 1)
            for ny in 0...bottomInit {
                let p = temp[ny * width + x]
                sumA += (p >> 24) & 0xFF
                sumR += (p >> 16) & 0xFF
                sumG += (p >> 8) & 0xFF
                sumB += p & 0xFF
                count += 1
            }
            
            // y=0
            var a = sumA / count
            var r = sumR / count
            var g = sumG / count
            var b = sumB / count
            pixels[0 * width + x] = (a << 24) | (r << 16) | (g << 8) | b
            
            if height == 1 { continue }
            
            // Slide window down the column
            for y in 1..<height {
                let outY = y - radius - 1
                if outY >= 0 {
                    let pOut = temp[outY * width + x]
                    sumA -= (pOut >> 24) & 0xFF
                    sumR -= (pOut >> 16) & 0xFF
                    sumG -= (pOut >> 8) & 0xFF
                    sumB -= pOut & 0xFF
                    count -= 1
                }
                let inY = y + radius
                if inY < height {
                    let pIn = temp[inY * width + x]
                    sumA += (pIn >> 24) & 0xFF
                    sumR += (pIn >> 16) & 0xFF
                    sumG += (pIn >> 8) & 0xFF
                    sumB += pIn & 0xFF
                    count += 1
                }
                a = sumA / count
                r = sumR / count
                g = sumG / count
                b = sumB / count
                pixels[y * width + x] = (a << 24) | (r << 16) | (g << 8) | b
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
        
        for i in 0..<pixels.size {
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
        let contrastFactor = max(Float(0.0), contrast)
        
        for i in 0..<pixels.size {
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
        
        for i in 0..<pixels.size {
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
extension kotlin.ByteArray {
    func toSwiftData() -> Data {
        return Data(platformValue: self)
    }
}
#endif
