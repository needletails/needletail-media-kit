import Foundation
#if SKIP
import SkipFoundation
#endif

/// Android-specific media compression implementation using Android MediaCodec APIs
public actor AndroidMediaCompressor {
    
    public init() {}
    
    public enum CompressionErrors: Error, Sendable {
        case failedToCreateExportSession
        case noVideoTrack
        case unsupportedFormat
        case compressionFailed(String)
    }
    
    public enum CompressionPreset: String, Sendable {
        case lowQuality = "low"
        case mediumQuality = "medium"
        case highQuality = "high"
        case highestQuality = "highest"
        
        case resolution640x480 = "640x480"
        case resolution960x540 = "960x540"
        case resolution1280x720 = "1280x720"
        case resolution1920x1080 = "1920x1080"
        case resolution3840x2160 = "3840x2160"
        
        public var targetSize: CGSize {
            switch self {
            case .lowQuality:
                return CGSize(width: 320, height: 240)
            case .mediumQuality:
                return CGSize(width: 640, height: 360)
            case .highQuality:
                return CGSize(width: 1280, height: 720)
            case .highestQuality:
                return CGSize(width: 1920, height: 1080)
            case .resolution640x480:
                return CGSize(width: 640, height: 480)
            case .resolution960x540:
                return CGSize(width: 960, height: 540)
            case .resolution1280x720:
                return CGSize(width: 1280, height: 720)
            case .resolution1920x1080:
                return CGSize(width: 1920, height: 1080)
            case .resolution3840x2160:
                return CGSize(width: 3840, height: 2160)
            }
        }
        
        public var bitrate: Int {
            switch self {
            case .lowQuality:
                return 500_000 // 500 kbps
            case .mediumQuality:
                return 1_000_000 // 1 Mbps
            case .highQuality:
                return 2_500_000 // 2.5 Mbps
            case .highestQuality:
                return 5_000_000 // 5 Mbps
            case .resolution640x480:
                return 1_000_000
            case .resolution960x540:
                return 1_500_000
            case .resolution1280x720:
                return 2_500_000
            case .resolution1920x1080:
                return 5_000_000
            case .resolution3840x2160:
                return 20_000_000 // 20 Mbps
            }
        }
    }
    
    /// Compresses a video file to the specified preset
    /// - Parameters:
    ///   - inputURL: The input video file URL
    ///   - presetName: The compression preset to use
    ///   - originalResolution: The original video resolution
    ///   - fileType: The input file type (MIME type string)
    ///   - outputFileType: The desired output file type (e.g., "mp4")
    /// - Returns: The URL of the compressed video file
    /// - Throws: CompressionErrors if compression fails
    nonisolated public func compressMedia(
        inputURL: URL,
        presetName: CompressionPreset,
        originalResolution: CGSize,
        fileType: String,
        outputFileType: String
    ) async throws -> URL {
        #if SKIP
        // Android implementation using MediaCodec, MediaExtractor, and MediaMuxer
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(outputFileType)
        
        // Calculate target resolution
        let targetSize = scaledResolution(for: originalResolution, using: presetName)
        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)
        let bitrate = presetName.bitrate
        
        // Get file path from URL
        let inputPath = inputURL.path
        let outputPath = outputURL.path
        
        // Setup MediaExtractor to read input video
        let extractor = android.media.MediaExtractor()
        extractor.setDataSource(inputPath)
        
        // Find video track
        var videoTrackIndex = -1
        var videoMimeType: String? = nil
        var videoFormat: android.media.MediaFormat? = nil
        
        for i in 0..<extractor.getTrackCount() {
            let format = extractor.getTrackFormat(i)
            let mime = format.getString(android.media.MediaFormat.KEY_MIME)
            if mime != nil && mime!.startsWith("video/") {
                videoTrackIndex = i
                videoMimeType = mime
                videoFormat = format
                break
            }
        }
        
        guard videoTrackIndex >= 0, let mimeType = videoMimeType, let inputFormat = videoFormat else {
            extractor.release()
            throw CompressionErrors.noVideoTrack
        }
        
        // Select the video track
        extractor.selectTrack(videoTrackIndex)
        
        // Get original video dimensions
        let originalWidth = inputFormat.getInteger(android.media.MediaFormat.KEY_WIDTH)
        let originalHeight = inputFormat.getInteger(android.media.MediaFormat.KEY_HEIGHT)
        
        // Determine output MIME type (prefer H.264/AVC for compatibility)
        let outputMimeType = "video/avc" // H.264
        
        // Create MediaCodec encoder
        let encoder = android.media.MediaCodec.createEncoderByType(outputMimeType)
        
        // Configure encoder format
        let encoderFormat = android.media.MediaFormat.createVideoFormat(
            outputMimeType,
            targetWidth,
            targetHeight
        )
        encoderFormat.setInteger(android.media.MediaFormat.KEY_COLOR_FORMAT, android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        encoderFormat.setInteger(android.media.MediaFormat.KEY_BIT_RATE, bitrate)
        encoderFormat.setInteger(android.media.MediaFormat.KEY_FRAME_RATE, 30) // 30 fps
        encoderFormat.setInteger(android.media.MediaFormat.KEY_I_FRAME_INTERVAL, 1) // I-frame interval
        
        // Configure encoder
        encoder.configure(encoderFormat, nil, nil, android.media.MediaCodec.CONFIGURE_FLAG_ENCODE)
        
        // Get input surface for encoder
        let inputSurface = encoder.createInputSurface()
        encoder.start()
        
        // Setup MediaMuxer for output
        let muxer = android.media.MediaMuxer(outputPath, android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        
        // For video compression with scaling, we use non-GPU Bitmap-based scaling:
        // 1. Use ImageReader to get Image objects from decoder (YUV format)
        // 2. Convert Image (YUV) to Bitmap (RGB) using YuvImage
        // 3. Scale Bitmap using Bitmap.createScaledBitmap() (CPU-based)
        // 4. Render scaled Bitmap to encoder's input surface using Canvas
        // 5. Encode and mux into output file
        
        // Check if scaling is needed
        let needsScaling = (originalWidth != targetWidth) || (originalHeight != targetHeight)
        
        // Setup decoder and ImageReader for scaling
        let decoderMimeType = mimeType
        let decoder = android.media.MediaCodec.createDecoderByType(decoderMimeType)
        
        var imageReader: android.media.ImageReader? = nil
        var decoderSurface: android.view.Surface? = nil
        
        if needsScaling {
            // For scaling: use ImageReader to get Image objects from decoder
            // ImageReader allows us to get frames as Image, which we can convert to Bitmap
            imageReader = android.media.ImageReader.newInstance(
                originalWidth,
                originalHeight,
                android.graphics.ImageFormat.YUV_420_888, // Common YUV format
                2 // Max images (double buffering)
            )
            decoderSurface = imageReader!.getSurface()
            decoder.configure(inputFormat, decoderSurface, nil, 0)
        } else {
            // No scaling needed - connect decoder output directly to encoder input surface
            decoder.configure(inputFormat, inputSurface, nil, 0)
        }
        
        decoder.start()
        
        // Processing state
        var inputEOS = false
        var decoderEOS = false
        var encoderEOS = false
        var muxerStarted = false
        var videoTrackIndexMuxer = -1
        
        // Process video frames
        while !encoderEOS {
            // Feed input data to decoder
            if !inputEOS {
                let inputBufferIndex = decoder.dequeueInputBuffer(10000) // 10ms timeout
                if inputBufferIndex >= 0 {
                    let inputBuffers = decoder.getInputBuffers()
                    let inputBuffer = inputBuffers[inputBufferIndex]
                    let sampleSize = extractor.readSampleData(inputBuffer, 0)
                    let sampleTime = extractor.getSampleTime()
                    
                    if sampleSize < 0 {
                        // End of input stream
                        decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputEOS = true
                    } else {
                        decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            
            // Process decoder output
            let decoderOutputBufferInfo = android.media.MediaCodec.BufferInfo()
            let decoderOutputBufferIndex = decoder.dequeueOutputBuffer(decoderOutputBufferInfo, 10000)
            
            if decoderOutputBufferIndex == android.media.MediaCodec.INFO_OUTPUT_FORMAT_CHANGED {
                // Decoder output format changed
            } else if decoderOutputBufferIndex >= 0 {
                // Decoded frame available
                if needsScaling {
                    // Get Image from ImageReader (non-blocking)
                    if let reader = imageReader {
                        let image = reader.acquireLatestImage()
                        if image != nil {
                            // Convert Image (YUV) to Bitmap (RGB)
                            let bitmap = imageToBitmap(image: image!)
                            
                            // Scale Bitmap using CPU-based scaling
                            let scaledBitmap = android.graphics.Bitmap.createScaledBitmap(
                                bitmap,
                                targetWidth,
                                targetHeight,
                                true // Use filtering for better quality
                            )
                            
                            // Render scaled Bitmap to encoder surface using Surface Canvas
                            let surfaceCanvas = inputSurface.lockCanvas(nil)
                            surfaceCanvas.drawBitmap(scaledBitmap, Float(0.0), Float(0.0), nil)
                            inputSurface.unlockCanvasAndPost(surfaceCanvas)
                            
                            // Cleanup
                            scaledBitmap.recycle()
                            bitmap.recycle()
                            image!.close()
                        }
                    }
                    
                    // Release decoder buffer
                    decoder.releaseOutputBuffer(decoderOutputBufferIndex, false)
                } else {
                    // No scaling - render directly to encoder's input surface
                    decoder.releaseOutputBuffer(decoderOutputBufferIndex, true) // render=true renders to surface
                }
                
                if (decoderOutputBufferInfo.flags & android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 {
                    decoderEOS = true
                    if !needsScaling {
                        // Signal encoder that input stream is complete
                        encoder.signalEndOfInputStream()
                    } else {
                        // For scaling case, signal encoder after processing all frames
                        encoder.signalEndOfInputStream()
                    }
                }
            }
            
            // Process encoder output
            let encoderOutputBufferInfo = android.media.MediaCodec.BufferInfo()
            let encoderOutputBufferIndex = encoder.dequeueOutputBuffer(encoderOutputBufferInfo, 10000)
            
            if encoderOutputBufferIndex == android.media.MediaCodec.INFO_OUTPUT_FORMAT_CHANGED {
                // Start muxer when we get the encoder format
                if !muxerStarted {
                    let encoderFormat = encoder.getOutputFormat()
                    videoTrackIndexMuxer = muxer.addTrack(encoderFormat)
                    muxer.start()
                    muxerStarted = true
                }
            } else if encoderOutputBufferIndex >= 0 {
                if encoderOutputBufferInfo.size != 0 && muxerStarted {
                    let outputBuffers = encoder.getOutputBuffers()
                    let outputBuffer = outputBuffers[encoderOutputBufferIndex]
                    outputBuffer.position(encoderOutputBufferInfo.offset)
                    outputBuffer.limit(encoderOutputBufferInfo.offset + encoderOutputBufferInfo.size)
                    
                    muxer.writeSampleData(videoTrackIndexMuxer, outputBuffer, encoderOutputBufferInfo)
                }
                
                encoder.releaseOutputBuffer(encoderOutputBufferIndex, false)
                
                if (encoderOutputBufferInfo.flags & android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 {
                    encoderEOS = true
                }
            }
        }
        
        // Cleanup resources
        if muxerStarted {
            muxer.stop()
        }
        muxer.release()
        encoder.stop()
        encoder.release()
        decoder.stop()
        decoder.release()
        extractor.release()
        inputSurface.release()
        if let reader = imageReader {
            reader.close()
        }
        if let surface = decoderSurface {
            surface.release()
        }
        
        return outputURL
        #else
        throw CompressionErrors.unsupportedFormat
        #endif
    }
    
    #if SKIP
    /// Converts an Android Image (YUV_420_888 format) to Bitmap (RGB format) for CPU-based processing
    /// - Parameter image: The Android Image in YUV_420_888 format
    /// - Returns: A Bitmap in RGB format
    private nonisolated func imageToBitmap(image: android.media.Image) -> android.graphics.Bitmap {
        let width = image.getWidth()
        let height = image.getHeight()
        
        // Get YUV planes from Image (YUV_420_888 format)
        let planes = image.getPlanes()
        let yBuffer = planes[0].getBuffer()
        let uBuffer = planes[1].getBuffer()
        let vBuffer = planes[2].getBuffer()
        
        // Get plane pixel strides and row strides
        let yPixelStride = planes[0].getPixelStride()
        let yRowStride = planes[0].getRowStride()
        let uPixelStride = planes[1].getPixelStride()
        let uRowStride = planes[1].getRowStride()
        let vPixelStride = planes[2].getPixelStride()
        let vRowStride = planes[2].getRowStride()
        
        // Create RGB bitmap
        let bitmap = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
        let pixels = kotlin.IntArray(size: width * height)
        
        // Save current buffer positions
        let yBufferPos = yBuffer.position()
        let uBufferPos = uBuffer.position()
        let vBufferPos = vBuffer.position()
        
        // Convert YUV_420_888 to RGB
        // YUV_420_888: Y plane is full resolution, U and V planes are half resolution
        for y in 0..<height {
            let yRowOffset = y * yRowStride
            let uvRowOffset = (y / 2) * uRowStride
            
            for x in 0..<width {
                let yOffset = yRowOffset + x * yPixelStride
                let uvOffset = uvRowOffset + (x / 2) * uPixelStride
                
                // Read Y, U, V values from buffers
                yBuffer.position(yOffset)
                uBuffer.position(uvOffset)
                vBuffer.position(uvOffset)
                
                let yVal = Int(yBuffer.get()) & 0xFF
                let uVal = Int(uBuffer.get()) & 0xFF
                let vVal = Int(vBuffer.get()) & 0xFF
                
                // YUV to RGB conversion (ITU-R BT.601)
                let c = yVal - 16
                let d = uVal - 128
                let e = vVal - 128
                
                var r = (298 * c + 409 * e + 128) >> 8
                var g = (298 * c - 100 * d - 208 * e + 128) >> 8
                var b = (298 * c + 516 * d + 128) >> 8
                
                // Clamp values to valid range
                r = max(0, min(255, r))
                g = max(0, min(255, g))
                b = max(0, min(255, b))
                
                // Set pixel (ARGB format: Alpha, Red, Green, Blue)
                pixels[y * width + x] = (0xFF << 24) | (r << 16) | (g << 8) | b
            }
        }
        
        // Restore buffer positions
        yBuffer.position(yBufferPos)
        uBuffer.position(uBufferPos)
        vBuffer.position(vBufferPos)
        
        // Set pixels to bitmap
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        
        return bitmap
    }
    #endif
    
    func scaledResolution(for originalSize: CGSize, using preset: CompressionPreset) -> CGSize {
        let isPortrait = originalSize.height > originalSize.width
        let presetSize = preset.targetSize
        let originalArea = originalSize.width * originalSize.height
        let presetArea = presetSize.width * presetSize.height
        
        // If the original area is smaller than the preset area, no scaling is needed.
        if originalArea < presetArea {
            return originalSize
        } else if isPortrait && originalArea > presetArea {
            // For portrait videos, swap the preset dimensions to preserve orientation.
            return CGSize(width: presetSize.height, height: presetSize.width)
        } else {
            return presetSize
        }
    }
}

