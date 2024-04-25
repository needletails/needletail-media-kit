//
//  ImageBlur.swift
//  NeedleTail
//
//  Created by Cole M on 5/27/23.

#if os(macOS) || os(iOS)
import Vision
import Accelerate
import CoreImage

fileprivate let kernelLength = 51

@available(iOS 16, macOS 13, *)
public actor BlurProcessor {
    public let imageProcessor = ImageProcessor()
    public init () {}
    
    private var cgImage: CGImage?
    
    private var mode = ConvolutionModes.hann1D
    
    private let machToSeconds: Double = {
        var timebase: mach_timebase_info_data_t = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) * 1e-9
    }()
    
    private var destinationBuffer = vImage_Buffer()
    
    private struct BlurObject: Sendable {
        var image: CGImage
        var format: vImage_CGImageFormat
        var blurSourceBuffer: vImage_Buffer
    }
    
    public enum ConvolutionModes: String, CaseIterable {
        case hann1D
        case hann2D
        case box
        case tent
        case multi
    }

    private var blurObject: BlurObject?
    private var pixelBuffer: CVPixelBuffer?
    private var blurIsSetup = false
    private var hasBlurred = false
    
    public enum BlurState: Sendable {
        case rerender, once
    }
    
    public var blurState: BlurState = .once
    
    private func setupBlur(_ cgImage: CGImage, pixelBuffer: CVPixelBuffer) async -> BlurObject? {
            
        func setup(_ pixelBuffer: CVPixelBuffer) -> BlurObject {
            guard let format = vImage_CGImageFormat(cgImage: cgImage) else { fatalError("forma nil") }
            guard
                var sourceImageBuffer = try? vImage_Buffer(cgImage: cgImage),
                
                    var scaledBuffer = try? vImage_Buffer(width: Int(sourceImageBuffer.width / 4),
                                                          height: Int(sourceImageBuffer.height / 4),
                                                          bitsPerPixel: format.bitsPerPixel
                    ) else {
                fatalError("Can't create source buffer.")
            }
            
            vImageScale_ARGB8888(&sourceImageBuffer,
                                 &scaledBuffer,
                                 nil,
                                 vImage_Flags(kvImageNoFlags))
            
            return BlurObject(image: cgImage, format: format, blurSourceBuffer: scaledBuffer)
        }
        return setup(pixelBuffer)
    }
    
    private let hannWindow: [Float] = {
        return vDSP.window(ofType: Float.self,
                           usingSequence: .hanningDenormalized,
                           count: kernelLength ,
                           isHalfWindow: false)
    }()
    
    lazy private var kernel1D: [Float] = {
        var multiplier = 1 / vDSP.sum(hannWindow)
        
        return vDSP.multiply(multiplier, hannWindow)
    }()
    
    lazy private var kernel2D: [Int16] = {
        let stride = vDSP_Stride(1)
        
        let intHann = vDSP.floatingPointToInteger(vDSP.multiply(pow(Float(Int16.max), 0.25), hannWindow),
                                                  integerType: Int16.self,
                                                  rounding: vDSP.RoundingMode.towardNearestInteger)
        
        var hannWindow2D = [Float](repeating: 0,
                                   count: kernelLength * kernelLength)
        
        if #available(iOS 16.4, macOS 13.3, *) {
            cblas_sger(CblasRowMajor,
                       Int32(kernelLength), Int32(kernelLength),
                       1, intHann.map { return Float($0) },
                       1, intHann.map { return Float($0) },
                       1,
                       &hannWindow2D,
                       Int32(kernelLength))
        } else {
            // Fallback on earlier versions
        }
        
        return vDSP.floatingPointToInteger(hannWindow2D,
                                           integerType: Int16.self,
                                           rounding: vDSP.RoundingMode.towardNearestInteger)
    }()
    
    @available(iOS 16.0, macOS 13, *)
    public func blurBackground(_ pixels: CVPixelBuffer, ciContext: CIContext) async throws -> (CIImage, CVPixelBuffer) {
        
        guard let image = try await imageProcessor.createCGImage(
            from: pixels,
            for: CGSize(width: pixels.width, height: pixels.height),
            desiredSize: CGSize(width: pixels.width, height: pixels.height),
            isThumbnail: false
        ) else {
            throw ImageErrors.cannotBlur
        }

           guard let blurObject = await setupBlur(image, pixelBuffer: pixels) else { throw ImageErrors.cannotBlur }
            return try await setBlur(
                with: .box,
                cgimage: blurObject.image,
                sourceBuffer: blurObject.blurSourceBuffer,
                format: blurObject.format,
                ciContext: ciContext
            )
    }
    
    @available(iOS 16.0, macOS 13, *)
    public func setBlur(with
                         mode: ConvolutionModes,
                         cgimage: CGImage,
                         sourceBuffer: vImage_Buffer,
                         format: vImage_CGImageFormat,
                         ciContext: CIContext
    ) async throws -> (CIImage, CVPixelBuffer) {
        self.mode = mode
        let image = try await applyBlur(cgimage, sourceBuffer: sourceBuffer, format: format)
        let ciImage = CIImage(cgImage: image)
        guard let buffer = await imageProcessor.recreatePixelBuffer(from: ciImage, ciContext: ciContext) else {
            throw ImageErrors.cannotBlur
        }
        return (ciImage, buffer)
    }
    
    @available(iOS 16.0, macOS 13, *)
    private func applyBlur(_ cgimage: CGImage, sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) async throws -> CGImage {
        destinationBuffer = try vImage_Buffer(width: Int(sourceBuffer.width),
                                              height: Int(sourceBuffer.height),
                                              bitsPerPixel: format.bitsPerPixel)
        
        switch mode {
        case .hann1D:
            hann1D(cgimage, sourceBuffer: sourceBuffer, format: format)
        case .hann2D:
            hann2D(sourceBuffer: sourceBuffer, format: format)
        case .tent:
            tent(sourceBuffer: sourceBuffer, format: format)
        case .box:
            box(sourceBuffer: sourceBuffer, format: format)
        case.multi:
            multi(sourceBuffer: sourceBuffer, format: format)
        }
        defer {
            destinationBuffer.free()
        }
        return try destinationBuffer.createCGImage(format: format)
    }
    
    
    @available(iOS 16.0, macOS 13, *)
    private func hann1D(_ cgImage: CGImage, sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
        var sourceBuffer = sourceBuffer
        
        let startTime = mach_absolute_time()
        
        let componentCount = format.componentCount
        
        var argbSourcePlanarBuffers: [vImage_Buffer] = (0 ..< componentCount).map { _ in
            guard let buffer = try? vImage_Buffer(width: Int(sourceBuffer.width),
                                                  height: Int(sourceBuffer.height),
                                                  bitsPerPixel: format.bitsPerComponent) else {
                fatalError("Error creating source buffers.")
            }
            
            return buffer
        }
        
        var argbDestinationPlanarBuffers: [vImage_Buffer] = (0 ..< componentCount).map { _ in
            guard let buffer = try? vImage_Buffer(width: Int(sourceBuffer.width),
                                                  height: Int(sourceBuffer.height),
                                                  bitsPerPixel: format.bitsPerComponent) else {
                fatalError("Error creating destination buffers.")
            }
            
            return buffer
        }
        
        vImageConvert_ARGB8888toPlanar8(&sourceBuffer,
                                        &argbSourcePlanarBuffers[0],
                                        &argbSourcePlanarBuffers[1],
                                        &argbSourcePlanarBuffers[2],
                                        &argbSourcePlanarBuffers[3],
                                        vImage_Flags(kvImageNoFlags))
        
        // Compute index of alpha channel and copy alpha with no convolution.
        let alphaIndex: Int?
        
        let littleEndian = cgImage.byteOrderInfo == .order16Little ||
        cgImage.byteOrderInfo == .order32Little
        
        switch cgImage.alphaInfo {
        case .first, .noneSkipFirst, .premultipliedFirst:
            alphaIndex = littleEndian ? componentCount - 1 : 0
        case .last, .noneSkipLast, .premultipliedLast:
            alphaIndex = littleEndian ? 0 : componentCount - 1
        default:
            alphaIndex = nil
        }
        
        if let alphaIndex = alphaIndex {
            do {
                try argbSourcePlanarBuffers[alphaIndex].copy(destinationBuffer: &argbDestinationPlanarBuffers[alphaIndex],
                                                             pixelSize: 1)
            } catch {
                fatalError("Error copying alpha buffer: \(error.localizedDescription).")
            }
        }
        
        // Separable convolution pass.
        for index in 0 ..< componentCount where index != alphaIndex {
            vImageSepConvolve_Planar8(&argbSourcePlanarBuffers[index],
                                      &argbDestinationPlanarBuffers[index],
                                      nil,
                                      0, 0,
                                      kernel1D, UInt32(kernel1D.count),
                                      kernel1D, UInt32(kernel1D.count),
                                      0, 0,
                                      vImage_Flags(kvImageEdgeExtend))
        }
        
        vImageConvert_Planar8toARGB8888(&argbDestinationPlanarBuffers[0],
                                        &argbDestinationPlanarBuffers[1],
                                        &argbDestinationPlanarBuffers[2],
                                        &argbDestinationPlanarBuffers[3],
                                        &destinationBuffer,
                                        vImage_Flags(kvImageNoFlags))
        
        // Free planar buffers.
        for buffer in argbSourcePlanarBuffers {
            buffer.free()
        }
        for buffer in argbDestinationPlanarBuffers {
            buffer.free()
        }
        
        let endTime = mach_absolute_time()
        print("hann1D", (machToSeconds * Double(endTime - startTime)))
    }
    
    private func hann2D(sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
        var sourceBuffer = sourceBuffer
        let divisor = kernel2D.map { Int32($0) }.reduce(0, +)
        
        let startTime = mach_absolute_time()
        
        vImageConvolve_ARGB8888(&sourceBuffer,
                                &destinationBuffer,
                                nil,
                                0, 0,
                                &kernel2D,
                                UInt32(kernelLength),
                                UInt32(kernelLength),
                                divisor,
                                nil,
                                vImage_Flags(kvImageEdgeExtend))
        
        let endTime = mach_absolute_time()
        print("hann2D", (machToSeconds * Double(endTime - startTime)))
    }
    
    private func tent(sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
        var sourceBuffer = sourceBuffer
        //        let startTime = mach_absolute_time()
        vImageTentConvolve_ARGB8888(&sourceBuffer,
                                    &destinationBuffer,
                                    nil,
                                    0, 0,
                                    UInt32(kernelLength),
                                    UInt32(kernelLength),
                                    nil,
                                    vImage_Flags(kvImageEdgeExtend))
        
        //        let endTime = mach_absolute_time()
        //        print("  tent", (machToSeconds * Double(endTime - startTime)))
    }
    
    private func box(sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
        var sourceBuffer = sourceBuffer
        //        let startTime = mach_absolute_time()
        
        vImageBoxConvolve_ARGB8888(&sourceBuffer,
                                   &destinationBuffer,
                                   nil,
                                   0, 0,
                                   UInt32(kernelLength),
                                   UInt32(kernelLength),
                                   nil,
                                   vImage_Flags(kvImageEdgeExtend))
        
        //        let endTime = mach_absolute_time()
        //        print("   box", (machToSeconds * Double(endTime - startTime)))
    }

    private func multi(sourceBuffer: vImage_Buffer, format: vImage_CGImageFormat) {
        var sourceBuffer = sourceBuffer
        
        let radius = kernelLength / 2
        let diameter = (radius * 2) + 1
        
        let kernels: [[Int16]] = (1 ... 4).map { index in
            var kernel = [Int16](repeating: 0,
                                 count: diameter * diameter)
            
            for x in 0 ..< diameter {
                for y in 0 ..< diameter {
                    if hypot(Float(radius - x), Float(radius - y)) < Float(radius / index) {
                        kernel[y * diameter + x] = 1
                    }
                }
            }
            
            return kernel
        }
        
        var divisors = kernels.map { return Int32($0.reduce(0, +)) }
        var biases: [Int32] = [0, 0, 0, 0]
        var backgroundColor: UInt8 = 0
        
        kernels[0].withUnsafeBufferPointer { zeroPtr in
            kernels[1].withUnsafeBufferPointer { onePtr in
                kernels[2].withUnsafeBufferPointer { twoPtr in
                    kernels[3].withUnsafeBufferPointer { threePtr in
                        
                        var kernels = [zeroPtr.baseAddress, onePtr.baseAddress,
                                       twoPtr.baseAddress, threePtr.baseAddress]
                        
                        _ = kernels.withUnsafeMutableBufferPointer { kernelsPtr in
                            vImageConvolveMultiKernel_ARGB8888(&sourceBuffer,
                                                               &destinationBuffer,
                                                               nil,
                                                               0, 0,
                                                               kernelsPtr.baseAddress!,
                                                               UInt32(diameter), UInt32(diameter),
                                                               &divisors,
                                                               &biases,
                                                               &backgroundColor,
                                                               vImage_Flags(kvImageEdgeExtend))
                        }
                    }
                }
            }
        }
    }
}

/* The following kernel, which is based on a Hann window, is suitable for use with an integer format. This isn't in the demo app. */

//private let kernel2D: [Int16] = [
//    0,    0,    0,      0,      0,      0,      0,
//    0,    2025, 6120,   8145,   6120,   2025,   0,
//    0,    6120, 18496,  24616,  18496,  6120,   0,
//    0,    8145, 24616,  32761,  24616,  8145,   0,
//    0,    6120, 18496,  24616,  18496,  6120,   0,
//    0,    2025, 6120,   8145,   6120,   2025,   0,
//    0,    0,    0,      0,      0,      0,      0
//]
//
//private let kernel1D: [Float] = [0, 45, 136, 181, 136, 45, 0]
#endif
