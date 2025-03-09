//#if os(macOS) || os(iOS)
////
////  ImageProcessor.swift
////  NeedleTail
////
////  Created by Cole M on 5/12/23.
////
//
//#if os(iOS)
//import UIKit
//#elseif os(macOS)
//import Cocoa
//#endif
//import Vision
//import CoreImage.CIFilterBuiltins
//@preconcurrency import Accelerate
//
public enum ImageErrors: Error {
    case imageCreationFailed(String)
}
//
//fileprivate let kernelLength = 51
//public actor ImageProcessor {
//    
//    private var cgImage: CGImage?
//    private var mode = ConvolutionModes.hann1D
//    private var destinationBuffer = vImage_Buffer()
//    private let machToSeconds: Double = {
//        var timebase: mach_timebase_info_data_t = mach_timebase_info_data_t()
//        mach_timebase_info(&timebase)
//        return Double(timebase.numer) / Double(timebase.denom) * 1e-9
//    }()
//    private var blurObject: BlurObject?
//    private var pixelBuffer: CVPixelBuffer?
//    private var blurIsSetup = false
//    private var hasBlurred = false
//    public var blurState: BlurState = .once
//    
//    private let pixelAttributes = [
//        kCVPixelBufferIOSurfacePropertiesKey: [
//            kCVPixelBufferCGImageCompatibilityKey: true,
//            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
//            kCVPixelBufferMetalCompatibilityKey: true,
//            kCMSampleAttachmentKey_DisplayImmediately: true
//        ]
//    ] as? CFDictionary
//    private let hannWindow: [Float] = {
//        return vDSP.window(ofType: Float.self,
//                           usingSequence: .hanningDenormalized,
//                           count: kernelLength ,
//                           isHalfWindow: false)
//    }()
//    
//    lazy private var kernel1D: [Float] = {
//        var multiplier = 1 / vDSP.sum(hannWindow)
//        
//        return vDSP.multiply(multiplier, hannWindow)
//    }()
//    
//    lazy private var kernel2D: [Int16] = {
//        let stride = vDSP_Stride(1)
//        
//        let intHann = vDSP.floatingPointToInteger(vDSP.multiply(pow(Float(Int16.max), 0.25), hannWindow),
//                                                  integerType: Int16.self,
//                                                  rounding: vDSP.RoundingMode.towardNearestInteger)
//        
//        var hannWindow2D = [Float](repeating: 0,
//                                   count: kernelLength * kernelLength)
//        
//        if #available(iOS 16.4, macOS 13.3, *) {
//            cblas_sger(CblasRowMajor,
//                       Int32(kernelLength), Int32(kernelLength),
//                       1, intHann.map { return Float($0) },
//                       1, intHann.map { return Float($0) },
//                       1,
//                       &hannWindow2D,
//                       Int32(kernelLength))
//        } else {
//            // Fallback on earlier versions
//        }
//        
//        return vDSP.floatingPointToInteger(hannWindow2D,
//                                           integerType: Int16.self,
//                                           rounding: vDSP.RoundingMode.towardNearestInteger)
//    }()
//    
//#if os(iOS) || os(macOS)
//    public func resize(_ imageData: Data, to desiredSize: CGSize, isThumbnail: Bool, ciContext: CIContext) async throws -> CGImage {
//        guard let ciimage = CIImage(data: imageData) else { throw ImageErrors.imageError }
//        guard let pb = recreatePixelBuffer(from: ciimage, ciContext: ciContext) else { throw ImageErrors.imageError }
//        guard let cgImage = try await createCGImage(from: pb, for: ciimage.extent.size, desiredSize: desiredSize, isThumbnail: isThumbnail) else { throw ImageErrors.imageError }
//        return cgImage
//    }
//#endif
//    
//#if os(macOS)
//    public func resize(_ imageData: NSImage, to desiredSize: CGSize, isThumbnail: Bool, ciContext: CIContext) async throws -> NSImage {
//        guard let cgImage = imageData.cgImage else { throw ImageErrors.imageError }
//        let ciimage = CIImage(cgImage: cgImage)
//        guard let pb = await recreatePixelBuffer(from: ciimage, ciContext: ciContext) else { throw ImageErrors.imageError }
//        guard let newCGImage = try await createCGImage(from: pb, for: imageData.size, desiredSize: desiredSize, isThumbnail: isThumbnail) else { throw ImageErrors.imageError }
//        return NSImage(cgImage: newCGImage, size: CGSize(width: newCGImage.width, height: newCGImage.height))
//    }
//#endif
//    
//    public func recreatePixelBuffer(from image: CIImage, ciContext: CIContext) -> CVPixelBuffer? {
//        var pixelBuffer: CVPixelBuffer? = nil
//        
//        CVPixelBufferCreate(
//            kCFAllocatorDefault,
//            Int(image.extent.width),
//            Int(image.extent.height),
//            kCVPixelFormatType_32BGRA,
//            pixelAttributes,
//            &pixelBuffer
//        )
//        guard let pixelBuffer = pixelBuffer else { return nil }
//        ciContext.render(image, to: pixelBuffer)
//        return pixelBuffer
//    }
//    
//    public func createCGImage(
//        from pixelBuffer: CVPixelBuffer,
//        for size: CGSize,
//        desiredSize: CGSize,
//        isThumbnail: Bool,
//        translate: Bool = false
//    ) async throws -> CGImage? {
//        let newSize = try await getNewSize(size: size, desiredSize: desiredSize, isThumbnail: isThumbnail)
//        // Define the image format
//        guard var format = vImage_CGImageFormat(
//            bitsPerComponent: 8,
//            bitsPerPixel: 32,
//            colorSpace: CGColorSpaceCreateDeviceRGB(),
//            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
//            renderingIntent: .defaultIntent
//        ) else {
//            throw vImage.Error.invalidImageFormat
//        }
//        var error: vImage_Error
//        var sourceBuffer = vImage_Buffer()
//        
//        guard let inputCVImageFormat = vImageCVImageFormat.make(buffer: pixelBuffer) else { throw vImage.Error.invalidCVImageFormat }
//        vImageCVImageFormat_SetColorSpace(inputCVImageFormat, CGColorSpaceCreateDeviceRGB())
//        
//        error = vImageBuffer_InitWithCVPixelBuffer(
//            &sourceBuffer,
//            &format,
//            pixelBuffer,
//            inputCVImageFormat,
//            nil,
//            vImage_Flags(kvImageNoFlags)
//        )
//        
//        guard error == kvImageNoError else {
//            throw vImage.Error(vImageError: error)
//        }
//        
//        // Our first destination must be the original bounds size this allows us to scale down the image with ratio to the desired scale type. We later center and crop the image to the correct width.
//        var destinationBuffer = try vImage_Buffer(
//            width: Int(newSize.width),
//            height: Int(newSize.height),
//            bitsPerPixel: format.bitsPerPixel
//        )
//        
//        // Scale the image
//        error = vImageScale_ARGB8888(&sourceBuffer,
//                                     &destinationBuffer,
//                                     nil,
//                                     vImage_Flags(kvImageHighQualityResampling))
//        guard error == kvImageNoError else {
//            throw vImage.Error(vImageError: error)
//        }
//        
//        var resizedImage: CGImage?
//        guard size != CGSize() else {
//            fatalError()
//        }
//        // Our new destination size must still be our intended final size that we insert media into. We cannot use the new scaled size because that is the media size not the container size.
//        var newDestination = try vImage_Buffer(
//            width: Int(desiredSize.width),
//            height: Int(desiredSize.height),
//            bitsPerPixel: format.bitsPerPixel
//        )
//        
//        // Center the image
//        if translate {
//            try centerImage(destinationBuffer, destination: &newDestination)
//            resizedImage = try newDestination.createCGImage(format: format)
//        } else {
//            resizedImage = try destinationBuffer.createCGImage(format: format)
//        }
//        
//        
//        defer {
//            sourceBuffer.free()
//            newDestination.free()
//            destinationBuffer.free()
//        }
//        
//        return resizedImage
//    }
//    
//    private func centerImage(_
//                             source: vImage_Buffer,
//                             destination: inout vImage_Buffer
//    ) throws {
//        
//        // 1. Calculate the translate required to center the buffer.
//        let sourceCenter = SIMD2<Double>(
//            x: Double(source.size.width / 2),
//            y: Double(source.size.height / 2))
//        
//        //Destination is the view size that the source needs to fit into
//        let desinationCenter = SIMD2<Double>(
//            x: Double(destination.size.width / 2),
//            y: Double(destination.size.height / 2))
//        
//        let tx = desinationCenter.x - sourceCenter.x * 1
//        let ty = desinationCenter.y - sourceCenter.y * 1
//        var clearColor: [Pixel_8] = [0, 0, 0, 0]
//        
//        // 2. Create the affine transform that represents the scale-translate.
//        var vImageTransform = vImage_CGAffineTransform(
//            a: 1,
//            b: 0,
//            c: 0,
//            d: 1,
//            tx: tx,
//            ty: ty
//        )
//        
//        _ = try withUnsafePointer(to: source) { srcPointer in
//            let error = vImageAffineWarpCG_ARGB8888(
//                srcPointer,
//                &destination,
//                nil,
//                &vImageTransform,
//                &clearColor,
//                vImage_Flags(kvImageBackgroundColorFill))
//            guard error == kvImageNoError else {
//                throw vImage.Error(vImageError: error)
//            }
//        }
//    }
//    
//    public func getAspectRatio(size: CGSize) -> CGFloat {
//        if size.width > size.height {
//            return size.width / size.height
//        } else {
//            return size.height / size.width
//        }
//    }
//    
//    public func getNewSize(data: Data? = nil, size: CGSize? = nil, desiredSize: CGSize? = nil, isThumbnail: Bool = false) async throws -> CGSize {
//        var size = size
//        var desiredSize = desiredSize
//        if size == nil, let data = data {
//            guard let ciThumbnail = CIImage(data: data) else { throw ImageErrors.cannotGetSize }
//            size = ciThumbnail.extent.size
//        }
//        if desiredSize == nil, let data = data {
//            guard let ciThumbnail = CIImage(data: data) else { throw ImageErrors.cannotGetSize }
//            desiredSize = ciThumbnail.extent.size
//        }
//        guard let size = size else { throw ImageErrors.cannotGetSize }
//        guard let desiredSize = desiredSize else { throw ImageErrors.cannotGetSize }
//        
//        let aspectRatio = getAspectRatio(size: size)
//        if size.height > size.width {
//            let height = desiredSize.width * aspectRatio
//            if height > 250 && isThumbnail {
//                return CGSize(width: 250 / aspectRatio, height: 250)
//            } else {
//                let width = desiredSize.height / aspectRatio
//                return CGSize(width: width, height: desiredSize.height)
//            }
//        } else {
//            let width = desiredSize.height * aspectRatio
//#if os(iOS)
//            let screenWidth = await Task { @MainActor in UIScreen.main.bounds.size.width }.value
//            if width > screenWidth {
//                let width = desiredSize.width
//                let height = desiredSize.width / aspectRatio
//                return CGSize(width: width, height: height)
//            }                else if width > 250 && isThumbnail {
//                return CGSize(width: 250, height: 250 / aspectRatio)
//            } else {
//                return CGSize(width: width, height: desiredSize.height)
//            }
//#elseif os(macOS)
//            let windowWidth = try await Task { @MainActor in NSApplication.shared.windows.first?.frame.width }.value
//            if width > windowWidth ?? 300 {
//                let width = desiredSize.width
//                let height = desiredSize.width / aspectRatio
//                return CGSize(width: width, height: height)
//            }                else if width > 250 && isThumbnail {
//                return CGSize(width: 250, height: 250 / aspectRatio)
//            } else {
//                return CGSize(width: width, height: desiredSize.height)
//            }
//#endif
//        }
//    }
//    
//    public func processImages(_
//                              pixelBuffer: CVPixelBuffer,
//                              backgroundBuffer: CVPixelBuffer,
//                              ciContext: CIContext
//    ) async throws -> ImageObject? {
//        // Create request handler
//        let mask: VNPixelBufferObservation = try autoreleasepool {
//            let request = VNGeneratePersonSegmentationRequest()
//            request.qualityLevel = .balanced
//            
//            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
//                                                orientation: .up,
//                                                options: [:])
//            
//            try handler.perform([request])
//            
//            guard let mask = request.results?.first else {
//                throw ImageErrors.imageError
//            }
//            return mask
//        }
//        return try await blendImages(
//            foregroundBuffer: pixelBuffer,
//            maskedBuffer: mask.pixelBuffer,
//            backgroundBuffer: backgroundBuffer,
//            ciContext: ciContext
//        )
//    }
//    
//    public struct ImageObject: @unchecked Sendable {
//        var buffer: CVPixelBuffer?
//        var image: CIImage?
//    }
//    
//    public func blendImages(
//        foregroundBuffer: CVPixelBuffer,
//        maskedBuffer: CVPixelBuffer,
//        backgroundBuffer: CVPixelBuffer,
//        ciContext: CIContext
//    ) async throws -> ImageObject? {
//        
//        guard let newForegroundBuffer = recreatePixelBuffer(from: CIImage(cvPixelBuffer: foregroundBuffer), ciContext: ciContext) else { return nil }
//        guard let newMaskedBuffer = recreatePixelBuffer(from: CIImage(cvPixelBuffer: maskedBuffer), ciContext: ciContext) else { return nil }
//        guard let newBackgroundBuffer = recreatePixelBuffer(from: CIImage(cvPixelBuffer: backgroundBuffer), ciContext: ciContext) else { return nil }
//        
//        let size = CGSize(
//            width: newForegroundBuffer.width,
//            height: newForegroundBuffer.height
//        )
//        
//        guard let resizedMask = try await createCGImage(
//            from: newMaskedBuffer,
//            for: size,
//            desiredSize: size,
//            isThumbnail: false
//        ) else { return nil }
//        guard let resizedBackground = try await createCGImage(
//            from: newBackgroundBuffer,
//            for: size,
//            desiredSize: size,
//            isThumbnail: false
//        ) else { return nil }
//        guard let resizedForeground = try await createCGImage(
//            from: newForegroundBuffer,
//            for: size,
//            desiredSize: size,
//            isThumbnail: false
//        ) else { return nil }
//        
//        let image: CIImage = autoreleasepool {
//            let blendFilter = CIFilter.blendWithMask()
//            blendFilter.inputImage = CIImage(cgImage: resizedForeground)
//            blendFilter.backgroundImage = CIImage(cgImage: resizedBackground)
//            blendFilter.maskImage = CIImage(cgImage: resizedMask)
//            
//            let image = blendFilter.outputImage
//            return image!
//        }
//        //        create pixel buffer
//        let buffer = recreatePixelBuffer(from: image, ciContext: ciContext)
//        return ImageObject(buffer: buffer, image: image)
//        
//    }
//    
//#if os(iOS)
//    @MainActor
//    public func fillParent(with aspectRatio: CGFloat, from imageData: UIImage) -> CGSize {
//        if imageData.size.height > imageData.size.width {
//            let width = UIScreen.main.bounds.size.width
//            let height = UIScreen.main.bounds.size.width * aspectRatio
//            return CGSize(width: width, height: height)
//        } else {
//            let width = UIScreen.main.bounds.size.width
//            let height = UIScreen.main.bounds.size.width / aspectRatio
//            return CGSize(width: width, height: height)
//        }
//    }
//#else
//    @MainActor
//    public func fillParent(with aspectRatio: CGFloat, from imageData: NSImage) -> CGSize {
//        guard let frame = NSScreen.main?.frame else { return CGSize() }
//        if imageData.size.height > imageData.size.width {
//            let width = frame.width
//            let height = frame.width * aspectRatio
//            return CGSize(width: width, height: height)
//        } else {
//            let width = frame.width
//            let height = frame.width / aspectRatio
//            return CGSize(width: width, height: height)
//        }
//    }
//#endif
//}
//#endif
//
//#if os(iOS) || os(macOS)
//extension ImageProcessor {
//    
//    public func resize(
//        cvImageBuffer: CVImageBuffer,
//        to desiredSize: CGSize,
//        isThumbnail: Bool,
//        ciContext: CIContext,
//        translate: Bool = false
//    ) async throws -> CGImage {
//        let ciimage = CIImage(cvImageBuffer: cvImageBuffer)
//        guard let pb = recreatePixelBuffer(
//            from: ciimage,
//            ciContext: ciContext
//        ) else { throw ImageErrors.imageError }
//        guard let cgImage = try await createCGImage(
//            from: pb,
//            for: ciimage.extent.size,
//            desiredSize: desiredSize,
//            isThumbnail: isThumbnail,
//            translate: translate
//        ) else { throw ImageErrors.imageError }
//        return cgImage
//    }
//    
//    public func resize(
//        cvPixelBuffer: CVPixelBuffer,
//        to desiredSize: CGSize,
//        isThumbnail: Bool,
//        ciContext: CIContext,
//        translate: Bool = false
//    ) async throws -> CGImage {
//        let ciimage = CIImage(cvPixelBuffer: cvPixelBuffer)
//        guard let pb = recreatePixelBuffer(
//            from: ciimage,
//            ciContext: ciContext
//        ) else { throw ImageErrors.imageError }
//        guard let cgImage = try await createCGImage(
//            from: pb,
//            for: ciimage.extent.size,
//            desiredSize: desiredSize,
//            isThumbnail: isThumbnail,
//            translate: translate
//        ) else { throw ImageErrors.imageError }
//        return cgImage
//    }
//    
//    public func createSampleBuffer(from pixelBuffer: CVPixelBuffer, time: CMTime) -> CMSampleBuffer? {
//        var sampleBuffer: CMSampleBuffer?
//        
//        // Create a format description for the pixel buffer
//        var formatDescription: CMFormatDescription?
//        CMVideoFormatDescriptionCreateForImageBuffer(
//            allocator: kCFAllocatorDefault,
//            imageBuffer: pixelBuffer,
//            formatDescriptionOut: &formatDescription
//        )
//        
//        // Create a CMSampleTimingInfo
//        var timingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
//        guard let formatDescription = formatDescription else { fatalError() }
//        // Create a CMSampleBuffer
//        CMSampleBufferCreateForImageBuffer(
//            allocator: kCFAllocatorDefault,
//            imageBuffer: pixelBuffer,
//            dataReady: true,
//            makeDataReadyCallback: nil,
//            refcon: nil,
//            formatDescription: formatDescription,
//            sampleTiming: &timingInfo,
//            sampleBufferOut: &sampleBuffer
//        )
//        
//        return sampleBuffer
//    }
//}
//
//extension ImageProcessor {
//    
//    public struct BlurObject: Sendable {
//        var image: CGImage
//        var format: vImage_CGImageFormat
//        var blurSourceBuffer: vImage_Buffer
//    }
//    
//    public enum ConvolutionModes: String, CaseIterable, Sendable {
//        case hann1D
//        case hann2D
//        case box
//        case tent
//        case multi
//    }
//    
//    public enum BlurState: Sendable {
//        case rerender, once
//    }
//    
//    private func setupBlur(_ cgImage: CGImage, pixelBuffer: CVPixelBuffer) async -> BlurObject? {
//        
//        func setup(_ pixelBuffer: CVPixelBuffer) -> BlurObject {
//            guard let format = vImage_CGImageFormat(cgImage: cgImage) else { fatalError("forma nil") }
//            guard
//                var sourceImageBuffer = try? vImage_Buffer(cgImage: cgImage),
//                
//                    var scaledBuffer = try? vImage_Buffer(width: Int(sourceImageBuffer.width / 4),
//                                                          height: Int(sourceImageBuffer.height / 4),
//                                                          bitsPerPixel: format.bitsPerPixel
//                    ) else {
//                fatalError("Can't create source buffer.")
//            }
//            
//            vImageScale_ARGB8888(&sourceImageBuffer,
//                                 &scaledBuffer,
//                                 nil,
//                                 vImage_Flags(kvImageNoFlags))
//            
//            return BlurObject(image: cgImage, format: format, blurSourceBuffer: scaledBuffer)
//        }
//        return setup(pixelBuffer)
//    }
//    
//    @available(iOS 16.0, macOS 13, *)
//    public func blurBackground(_ pixels: CVPixelBuffer, ciContext: CIContext) async throws -> (CIImage, CVPixelBuffer) {
//        guard let image = try await createCGImage(
//            from: pixels,
//            for: CGSize(width: pixels.width, height: pixels.height),
//            desiredSize: CGSize(width: pixels.width, height: pixels.height),
//            isThumbnail: false
//        ) else {
//            throw ImageErrors.cannotBlur
//        }
//        
//        guard let blurObject = await setupBlur(image, pixelBuffer: pixels) else { throw ImageErrors.cannotBlur }
//        return try await setBlur(
//            with: .box,
//            cgimage: blurObject.image,
//            sourceBuffer: blurObject.blurSourceBuffer,
//            format: blurObject.format,
//            ciContext: ciContext
//        )
//    }
//    
//    @available(iOS 16.0, macOS 13, *)
//    public func setBlur(with
//                        mode: ConvolutionModes,
//                        cgimage: CGImage,
//                        sourceBuffer: vImage_Buffer,
//                        format: vImage_CGImageFormat,
//                        ciContext: CIContext
//    ) async throws -> (CIImage, CVPixelBuffer) {
//        self.mode = mode
//        let image = try await applyBlur(cgimage, sourceBuffer: sourceBuffer, format: format)
//        let ciImage = CIImage(cgImage: image)
//        guard let buffer = recreatePixelBuffer(from: ciImage, ciContext: ciContext) else {
//            throw ImageErrors.cannotBlur
//        }
//        return (ciImage, buffer)
//    }
//    
//    @available(iOS 16.0, macOS 13, *)
//    private func applyBlur(_ cgimage: CGImage, sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) async throws -> CGImage {
//        destinationBuffer = try vImage_Buffer(width: Int(sourceBuffer.width),
//                                              height: Int(sourceBuffer.height),
//                                              bitsPerPixel: format.bitsPerPixel)
//        
//        switch mode {
//        case .hann1D:
//            hann1D(cgimage, sourceBuffer: sourceBuffer, format: format)
//        case .hann2D:
//            hann2D(sourceBuffer: sourceBuffer, format: format)
//        case .tent:
//            tent(sourceBuffer: sourceBuffer, format: format)
//        case .box:
//            box(sourceBuffer: sourceBuffer, format: format)
//        case.multi:
//            multi(sourceBuffer: sourceBuffer, format: format)
//        }
//        defer {
//            destinationBuffer.free()
//        }
//        return try destinationBuffer.createCGImage(format: format)
//    }
//    
//    
//    @available(iOS 16.0, macOS 13, *)
//    private func hann1D(_ cgImage: CGImage, sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
//        var sourceBuffer = sourceBuffer
//        
//        let startTime = mach_absolute_time()
//        
//        let componentCount = format.componentCount
//        
//        var argbSourcePlanarBuffers: [vImage_Buffer] = (0 ..< componentCount).map { _ in
//            guard let buffer = try? vImage_Buffer(width: Int(sourceBuffer.width),
//                                                  height: Int(sourceBuffer.height),
//                                                  bitsPerPixel: format.bitsPerComponent) else {
//                fatalError("Error creating source buffers.")
//            }
//            
//            return buffer
//        }
//        
//        var argbDestinationPlanarBuffers: [vImage_Buffer] = (0 ..< componentCount).map { _ in
//            guard let buffer = try? vImage_Buffer(width: Int(sourceBuffer.width),
//                                                  height: Int(sourceBuffer.height),
//                                                  bitsPerPixel: format.bitsPerComponent) else {
//                fatalError("Error creating destination buffers.")
//            }
//            
//            return buffer
//        }
//        
//        vImageConvert_ARGB8888toPlanar8(&sourceBuffer,
//                                        &argbSourcePlanarBuffers[0],
//                                        &argbSourcePlanarBuffers[1],
//                                        &argbSourcePlanarBuffers[2],
//                                        &argbSourcePlanarBuffers[3],
//                                        vImage_Flags(kvImageNoFlags))
//        
//        // Compute index of alpha channel and copy alpha with no convolution.
//        let alphaIndex: Int?
//        
//        let littleEndian = cgImage.byteOrderInfo == .order16Little ||
//        cgImage.byteOrderInfo == .order32Little
//        
//        switch cgImage.alphaInfo {
//        case .first, .noneSkipFirst, .premultipliedFirst:
//            alphaIndex = littleEndian ? componentCount - 1 : 0
//        case .last, .noneSkipLast, .premultipliedLast:
//            alphaIndex = littleEndian ? 0 : componentCount - 1
//        default:
//            alphaIndex = nil
//        }
//        
//        if let alphaIndex = alphaIndex {
//            do {
//                try argbSourcePlanarBuffers[alphaIndex].copy(destinationBuffer: &argbDestinationPlanarBuffers[alphaIndex],
//                                                             pixelSize: 1)
//            } catch {
//                fatalError("Error copying alpha buffer: \(error.localizedDescription).")
//            }
//        }
//        
//        // Separable convolution pass.
//        for index in 0 ..< componentCount where index != alphaIndex {
//            vImageSepConvolve_Planar8(&argbSourcePlanarBuffers[index],
//                                      &argbDestinationPlanarBuffers[index],
//                                      nil,
//                                      0, 0,
//                                      kernel1D, UInt32(kernel1D.count),
//                                      kernel1D, UInt32(kernel1D.count),
//                                      0, 0,
//                                      vImage_Flags(kvImageEdgeExtend))
//        }
//        
//        vImageConvert_Planar8toARGB8888(&argbDestinationPlanarBuffers[0],
//                                        &argbDestinationPlanarBuffers[1],
//                                        &argbDestinationPlanarBuffers[2],
//                                        &argbDestinationPlanarBuffers[3],
//                                        &destinationBuffer,
//                                        vImage_Flags(kvImageNoFlags))
//        
//        // Free planar buffers.
//        for buffer in argbSourcePlanarBuffers {
//            buffer.free()
//        }
//        for buffer in argbDestinationPlanarBuffers {
//            buffer.free()
//        }
//        
//        let endTime = mach_absolute_time()
//        print("hann1D", (machToSeconds * Double(endTime - startTime)))
//    }
//    
//    private func hann2D(sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
//        var sourceBuffer = sourceBuffer
//        let divisor = kernel2D.map { Int32($0) }.reduce(0, +)
//        var kernel2D = kernel2D
//        let startTime = mach_absolute_time()
//        
//        vImageConvolve_ARGB8888(&sourceBuffer,
//                                &destinationBuffer,
//                                nil,
//                                0, 0,
//                                &kernel2D,
//                                UInt32(kernelLength),
//                                UInt32(kernelLength),
//                                divisor,
//                                nil,
//                                vImage_Flags(kvImageEdgeExtend))
//        
//        let endTime = mach_absolute_time()
//        print("hann2D", (machToSeconds * Double(endTime - startTime)))
//    }
//    
//    private func tent(sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
//        var sourceBuffer = sourceBuffer
//        //        let startTime = mach_absolute_time()
//        vImageTentConvolve_ARGB8888(&sourceBuffer,
//                                    &destinationBuffer,
//                                    nil,
//                                    0, 0,
//                                    UInt32(kernelLength),
//                                    UInt32(kernelLength),
//                                    nil,
//                                    vImage_Flags(kvImageEdgeExtend))
//        
//        //        let endTime = mach_absolute_time()
//        //        print("  tent", (machToSeconds * Double(endTime - startTime)))
//    }
//    
//    private func box(sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
//        var sourceBuffer = sourceBuffer
//        //        let startTime = mach_absolute_time()
//        
//        vImageBoxConvolve_ARGB8888(&sourceBuffer,
//                                   &destinationBuffer,
//                                   nil,
//                                   0, 0,
//                                   UInt32(kernelLength),
//                                   UInt32(kernelLength),
//                                   nil,
//                                   vImage_Flags(kvImageEdgeExtend))
//        
//        //        let endTime = mach_absolute_time()
//        //        print("   box", (machToSeconds * Double(endTime - startTime)))
//    }
//    
//    private func multi(sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
//        var sourceBuffer = sourceBuffer
//        
//        let radius = kernelLength / 2
//        let diameter = (radius * 2) + 1
//        
//        let kernels: [[Int16]] = (1 ... 4).map { index in
//            var kernel = [Int16](repeating: 0,
//                                 count: diameter * diameter)
//            
//            for x in 0 ..< diameter {
//                for y in 0 ..< diameter {
//                    if hypot(Float(radius - x), Float(radius - y)) < Float(radius / index) {
//                        kernel[y * diameter + x] = 1
//                    }
//                }
//            }
//            
//            return kernel
//        }
//        
//        var divisors = kernels.map { return Int32($0.reduce(0, +)) }
//        var biases: [Int32] = [0, 0, 0, 0]
//        var backgroundColor: UInt8 = 0
//        
//        kernels[0].withUnsafeBufferPointer { zeroPtr in
//            kernels[1].withUnsafeBufferPointer { onePtr in
//                kernels[2].withUnsafeBufferPointer { twoPtr in
//                    kernels[3].withUnsafeBufferPointer { threePtr in
//                        
//                        var kernels = [zeroPtr.baseAddress, onePtr.baseAddress,
//                                       twoPtr.baseAddress, threePtr.baseAddress]
//                        
//                        _ = kernels.withUnsafeMutableBufferPointer { kernelsPtr in
//                            vImageConvolveMultiKernel_ARGB8888(&sourceBuffer,
//                                                               &destinationBuffer,
//                                                               nil,
//                                                               0, 0,
//                                                               kernelsPtr.baseAddress!,
//                                                               UInt32(diameter), UInt32(diameter),
//                                                               &divisors,
//                                                               &biases,
//                                                               &backgroundColor,
//                                                               vImage_Flags(kvImageEdgeExtend))
//                        }
//                    }
//                }
//            }
//        }
//    }
//#if os(iOS)
//    public func blurImage(cgImage: CGImage?, ciContext: CIContext) async throws -> UIImage {
//        guard let cgImage = cgImage else { fatalError("CGImage is nil") }
//        guard let pixelBuffer = self.recreatePixelBuffer(
//            from: CIImage(cgImage: cgImage),
//            ciContext: ciContext
//        ) else { fatalError("Couldn't create pixelBuffer") }
//        let info = try await self.blurBackground(pixelBuffer, ciContext: ciContext)
//        return UIImage(ciImage: info.0)
//    }
//#endif
//}
//#endif
