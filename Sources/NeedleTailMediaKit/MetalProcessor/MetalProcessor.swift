#if canImport(Metal) && canImport(Accelerate) && canImport(Vision)
//
//  MetalProcessor.swift
//
//
//  Created by Cole M on 6/24/24.
//
@preconcurrency import Metal
@preconcurrency import MetalPerformanceShaders
@preconcurrency import Accelerate
import MetalKit
import CoreMedia.CMTime
import Vision
import Foundation
import NeedleTailLogger
import CoreImage
#if canImport(UIKit)
import UIKit
#endif

/// Matches `PQSRTCDiagnostics.remoteVideoTraceLoggingEnabled` in PQSRTC: DEBUG on by default, Release when
/// `PQSRTC_REMOTE_VIDEO_TRACE_LOGGING=1`.
private enum RemoteVideoTraceLogging {
    static var enabled: Bool {
#if DEBUG
        true
#else
        ProcessInfo.processInfo.environment["PQSRTC_REMOTE_VIDEO_TRACE_LOGGING"] == "1"
#endif
    }

    /// `.trace` minimum so `log(level: .trace, …)` is not filtered by the logger threshold.
    static let logger = NeedleTailLogger("[MetalProcessor:RemoteVideo]", level: .trace)
}

public actor MetalProcessor {
    
    enum MetalScalingErrors: Error, Sendable {
        case metalNotSupported, failedToCreateTextureCache, failedToCreateTextureCacheFromImage, failedToCreateTexture, failedToUnwrapTexture, failedToUnwrapTextureCache, failedToGetTexture, errorSettingUpEncoder, errorSettingUpCommandQueue, shaderFunctionNotFound, failedToCreateDataProvider, failedToCreateOutputPixelBuffer, failedToCreatePixelBufferPool, failedToLockPixelBuffer, failedToCreatePipeline, sampleBufferCreationError
        case pixelBufferCreationError, cannotProcessBackgroundImage, imageCreationFailed
    }
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let textureLoader: MTKTextureLoader
    let textureCache: CVMetalTextureCache
    
    // Reuse CVPixelBufferPools by (format, width, height) to avoid per-call pool creation.
    private struct PixelBufferPoolKey: Hashable, Sendable {
        let pixelFormat: OSType
        let width: Int
        let height: Int
        let metalCompatible: Bool
    }
    private var pixelBufferPoolCache: [PixelBufferPoolKey: CVPixelBufferPool] = [:]
    private func pixelBufferPool(
        pixelFormat: OSType,
        width: Int,
        height: Int,
        metalCompatible: Bool
    ) throws -> CVPixelBufferPool {
        let key = PixelBufferPoolKey(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            metalCompatible: metalCompatible
        )
        if let existing = pixelBufferPoolCache[key] { return existing }
        
        var attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        if metalCompatible {
            attributes[kCVPixelBufferMetalCompatibilityKey as String] = true
        }
        
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let created = pool else {
            throw MetalScalingErrors.failedToCreatePixelBufferPool
        }
        pixelBufferPoolCache[key] = created
        return created
    }
    var flipKernelPipeline: MTLComputePipelineState?
    var ycbcrToRgbKernelPipeline: MTLComputePipelineState?
    var twoVUYToRgbKernelPipeline: MTLComputePipelineState?
    var rgbToYuvKernelPipeline: MTLComputePipelineState?
    var i420ToRgbKernelPipeline: MTLComputePipelineState?
    var blurPipelineState: MTLComputePipelineState?
    let colorSpace: [CIImageOption: Any] = [CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB()]
    lazy var textureRenderContext: CIContext = {
        CIContext(
            mtlDevice: device,
            options: [
                .useSoftwareRenderer: false,
                .cacheIntermediates: false
            ]
        )
    }()
    private var didLogIOSCVPixelBufferConversion = false
    private var didLogIOSI420Conversion = false
    private var i420PlaneUploadLogCount = 0

    var destinationBuffer = vImage_Buffer()
    private var destinationBufferWidth = 0
    private var destinationBufferHeight = 0
    var cgImageFormat = vImage_CGImageFormat(bitsPerComponent: 8,
                                                          bitsPerPixel: 32,
                                                          colorSpace: nil,
                                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
                                                          version: 0,
                                                          decode: nil,
                                                          renderingIntent: .defaultIntent)
    
    public static var isSupported: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    public init() {
        do {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw MetalScalingErrors.metalNotSupported
            }
            self.device = device

            do {
                self.library = try device.makeDefaultLibrary(bundle: Bundle.module)
            } catch {
                // SwiftPM/Xcode sometimes won't produce a default metallib for package resources.
                // Fall back to compiling the bundled .metal source at runtime.
                guard let shaderURL = Bundle.module.url(forResource: "ImageShaders", withExtension: "metal") else {
                    throw error
                }
                let source = try String(contentsOf: shaderURL, encoding: .utf8)
                self.library = try device.makeLibrary(source: source, options: nil)
            }
            guard let commandQueue = device.makeCommandQueue() else {
                throw MetalScalingErrors.errorSettingUpCommandQueue
            }
            self.commandQueue = commandQueue
            self.textureLoader = MTKTextureLoader(device: device)
            
            var cache: CVMetalTextureCache?
            guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
                  let unwrapped = cache else {
                throw MetalScalingErrors.failedToCreateTextureCache
            }
            self.textureCache = unwrapped
            _ = configureYpCbCrToARGBInfo()
        } catch {
            fatalError("Metal Not Supported: \(error)")
        }
    }
    
    #if os(iOS) && canImport(Vision)
    /// Cached Vision request (actor-isolated). Avoids repeated allocation/config each frame.
    @available(iOS 15.0, *)
    private var personSegmentationRequest: VNGeneratePersonSegmentationRequest?
    #endif
    
    public func createTexture(from pixelBuffer: CVPixelBuffer, device: MTLDevice) throws -> MTLTexture {
        var texture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        // Use the actor-scoped cache (much cheaper than re-creating per call).
        let textureCache = self.textureCache
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &texture) == kCVReturnSuccess else {
            throw MetalScalingErrors.failedToCreateTextureCacheFromImage
        }
        guard let texture = texture else {
            throw MetalScalingErrors.failedToUnwrapTexture
        }
        guard let metalTexture = CVMetalTextureGetTexture(texture) else {
            throw MetalScalingErrors.failedToGetTexture
        }
        return metalTexture
    }
    
    private func createTextureViaCoreImage(from pixelBuffer: CVPixelBuffer) throws -> MTLTexture {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        textureRenderContext.render(
            ciImage,
            to: texture,
            commandBuffer: nil,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return texture
    }
    
    nonisolated(unsafe) internal var infoYpCbCrToARGB = vImage_YpCbCrToARGB()
    
    /// This method uses the Accelerate Framework into rder to set up the conversion of YUV data to RGB data
    /// - Returns: A type for image errors.
     nonisolated internal func configureYpCbCrToARGBInfo() -> vImage_Error {
        var pixelRange = vImage_YpCbCrPixelRange(Yp_bias: 16,
                                                 CbCr_bias: 128,
                                                 YpRangeMax: 235,
                                                 CbCrRangeMax: 240,
                                                 YpMax: 235,
                                                 YpMin: 16,
                                                 CbCrMax: 240,
                                                 CbCrMin: 16)
        
        let error = vImageConvert_YpCbCrToARGB_GenerateConversion(
            kvImage_YpCbCrToARGBMatrix_ITU_R_709_2!,
            &pixelRange,
            &self.infoYpCbCrToARGB,
            kvImage422CbYpCrYp8,
            kvImageARGB8888,
            vImage_Flags(kvImageNoFlags))
        
        return error
    }

    internal func convert2VUYToCVPixelBuffer(_ pixelBuffer: CVPixelBuffer, ciContext: CIContext) async throws -> CVPixelBuffer? {
        _ = pixelBuffer.metalPixelFormat
        var error = kvImageNoError
        
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            throw MetalScalingErrors.failedToLockPixelBuffer
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Ensure the pixel format is 2VUY (YUV 4:2:2 interleaved)
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_422YpCbCr8 else {
            throw NSError(domain: "Invalid pixel format", code: -1, userInfo: nil)
        }

        // Get base address of 2VUY data (interleaved YUV422)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "Failed to get base address", code: -1, userInfo: nil)
        }
        
        // Create source vImage buffer for 2VUY
        var srcBuffer = vImage_Buffer(
            data: baseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: bytesPerRow
        )
        
        // Allocate the destination buffer (RGB)
        if destinationBuffer.data == nil || destinationBufferWidth != width || destinationBufferHeight != height {
            if destinationBuffer.data != nil {
                free(destinationBuffer.data)
            }
            error = vImageBuffer_Init(&destinationBuffer,
                                      vImagePixelCount(height),
                                      vImagePixelCount(width),
                                      32, // 32-bit ARGB
                                      vImage_Flags(kvImageNoFlags))
            
            guard error == kvImageNoError else {
                return nil
            }
            destinationBufferWidth = width
            destinationBufferHeight = height
        }
        
        // Temporary vImage buffer pointing to destination
        _ = vImage_Buffer(
            data: destinationBuffer.data,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: destinationBuffer.rowBytes
        )
     
        // Perform YUV422 (2VUY) → RGB conversion
        error = vImageConvert_422CbYpCrYp8ToARGB8888(
               &srcBuffer,
               &destinationBuffer,
               &infoYpCbCrToARGB,
               nil,  // No permute map
               255,  // Full alpha
               vImage_Flags(kvImageNoFlags)
           )

        guard error == kvImageNoError else {
            throw NSError(domain: "vImage conversion failed", code: Int(error), userInfo: nil)
        }

        // Create a CVPixelBuffer for the RGB output
        guard let outputPixelBuffer = try await createPixelBuffer(width: width, height: height, ciContext: ciContext) else {
            throw NSError(domain: "Failed to create RGB pixel buffer", code: -1, userInfo: nil)
        }
        
        CVBufferPropagateAttachments(pixelBuffer, outputPixelBuffer)
        
        let metadataKeys: [CFString] = [
                kCVImageBufferYCbCrMatrixKey,
                kCVImageBufferColorPrimariesKey,
                kCVImageBufferTransferFunctionKey,
                kCGImagePropertyExifDictionary
            ]

                    for key in metadataKeys {
            if let value = CVBufferCopyAttachment(pixelBuffer, key, nil) {
                CVBufferSetAttachment(outputPixelBuffer, key, value, .shouldPropagate)
            }
        }
        
        // Copy converted data into CVPixelBuffer
        guard let outputCVImageFormat = vImageCVImageFormat.make(buffer: outputPixelBuffer) else {
            throw vImage.Error.invalidCVImageFormat
        }
        
        vImageCVImageFormat_SetColorSpace(outputCVImageFormat, CGColorSpaceCreateDeviceRGB())

        error = vImageBuffer_CopyToCVPixelBuffer(
            &destinationBuffer,
            &cgImageFormat,
            outputPixelBuffer,
            outputCVImageFormat,
            nil,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else {
            throw NSError(domain: "vImageBuffer_CopyToCVPixelBuffer failed", code: Int(error), userInfo: nil)
        }

        return outputPixelBuffer
    }
    
    private let pixelAttributes = [
        kCVPixelBufferIOSurfacePropertiesKey: [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCMSampleAttachmentKey_DisplayImmediately: true,
        ]
    ] as? CFDictionary
    
    internal func createPixelBuffer(width: Int, height: Int, ciContext: CIContext) async throws -> CVPixelBuffer? {
        
        var pixelBuffer: CVPixelBuffer? = nil
        for await _ in withAutoreleasePool() {
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                pixelAttributes,
                &pixelBuffer
            )
        }
        
        guard let pixelBuffer = pixelBuffer else {
            throw MetalScalingErrors.failedToCreateOutputPixelBuffer
        }
        return pixelBuffer
    }
    
    func withAutoreleasePool() -> AsyncStream<Void> {
        return AsyncStream { continuation in
            autoreleasepool {
                continuation.yield()
                continuation.finish()
            }
        }
    }

    
    fileprivate func convert2VUYToRGB(
        cvPixelBuffer: CVPixelBuffer,
        device: MTLDevice
    ) throws -> MTLTexture {
        let cache = self.textureCache
        
        // Lock the base address of the CVPixelBuffer
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(cvPixelBuffer, .readOnly) else {
            throw MetalScalingErrors.failedToLockPixelBuffer
        }
        
        defer {
            // Always unlock the CVPixelBuffer
            CVPixelBufferUnlockBaseAddress(cvPixelBuffer, .readOnly)
        }
        
        // Create a Metal texture for the interleaved YUV data
        let yuvTexture = try createMTLTextureForPlane(
            cvPixelBuffer: cvPixelBuffer,
            planeIndex: 0, // Only one plane for 2vuy
            textureCache: cache,
            format: .bgrg422, // Adjust format as needed for your shader
            device: device)
        
        // Create a Metal texture for RGB output
        let rgbTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: CVPixelBufferGetWidth(cvPixelBuffer),
            height: CVPixelBufferGetHeight(cvPixelBuffer),
            mipmapped: false)
        rgbTextureDescriptor.usage = [.shaderRead, .shaderWrite]

        guard let rgbTexture = device.makeTexture(descriptor: rgbTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }

        // Create a Metal compute pipeline with a shader that converts YUV to RGB
        if twoVUYToRgbKernelPipeline == nil {
            twoVUYToRgbKernelPipeline = try createComputePipeline(device: device, shaderName: "ycbcrToRGBKernel")
        }
        
        // Set up a command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalScalingErrors.errorSettingUpEncoder
        }
        
        guard let twoVUYToRgbKernelPipeline = twoVUYToRgbKernelPipeline else {
            throw MetalScalingErrors.failedToCreatePipeline
        }
    
        // Set textures and encode the compute shader
        computeEncoder.setComputePipelineState(twoVUYToRgbKernelPipeline)
        computeEncoder.setTexture(yuvTexture, index: 0) // Use the interleaved YUV texture
        computeEncoder.setTexture(rgbTexture, index: 1) // Output RGB texture
        
        let w = twoVUYToRgbKernelPipeline.threadExecutionWidth
        let h = max(1, twoVUYToRgbKernelPipeline.maxTotalThreadsPerThreadgroup / w)
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: rgbTexture.width, height: rgbTexture.height, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        defer {
            computeEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        // Return the RGB texture
        return rgbTexture
    }
    
    public func convertYUVToRGB(
        cvPixelBuffer: CVPixelBuffer,
        device: MTLDevice
    ) throws -> MTLTexture {
        let cache = self.textureCache
        
        // Lock the base address of the CVPixelBuffer
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(cvPixelBuffer, .readOnly) else {
            throw MetalScalingErrors.failedToLockPixelBuffer
        }
        
        defer {
            // Always unlock the CVPixelBuffer
            CVPixelBufferUnlockBaseAddress(cvPixelBuffer, .readOnly)
        }
        
        // Create Metal textures for Y and UV planes
        let yTexture = try createMTLTextureForPlane(
            cvPixelBuffer: cvPixelBuffer,
            planeIndex: 0,
            textureCache: cache,
            format: .r8Unorm,
            device: device)
        
        let uvTexture = try createMTLTextureForPlane(
            cvPixelBuffer: cvPixelBuffer,
            planeIndex: 1,
            textureCache: cache,
            format: .rg8Unorm,
            device: device)
        
        // Create a Metal texture for RGB output
        let rgbTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: CVPixelBufferGetWidth(cvPixelBuffer),
            height: CVPixelBufferGetHeight(cvPixelBuffer),
            mipmapped: false)
        rgbTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let rgbTexture = device.makeTexture(descriptor: rgbTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        // Create a Metal compute pipeline with a shader that converts YUV to RGB
        if ycbcrToRgbKernelPipeline == nil {
            ycbcrToRgbKernelPipeline = try createComputePipeline(device: device, shaderName: "ycbcrToRgb")
        }
        // Set up a command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalScalingErrors.errorSettingUpEncoder
        }
        
        guard let ycbcrToRgbKernelPipeline = ycbcrToRgbKernelPipeline else {
            throw MetalScalingErrors.failedToCreatePipeline
        }
        // Set textures and encode the compute shader
        computeEncoder.setComputePipelineState(ycbcrToRgbKernelPipeline)
        computeEncoder.setTexture(yTexture, index: 0)
        computeEncoder.setTexture(uvTexture, index: 1)
        computeEncoder.setTexture(rgbTexture, index: 2)
        
        let w = ycbcrToRgbKernelPipeline.threadExecutionWidth
        let h = max(1, ycbcrToRgbKernelPipeline.maxTotalThreadsPerThreadgroup / w)
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: rgbTexture.width, height: rgbTexture.height, depth: 1)
        defer {
            computeEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        
        // Return the RGB texture
        return rgbTexture
    }
    
    public func convertPlanar420ToRGB(
        cvPixelBuffer: CVPixelBuffer,
        device: MTLDevice
    ) throws -> MTLTexture {
        let cache = self.textureCache
        
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(cvPixelBuffer, .readOnly) else {
            throw MetalScalingErrors.failedToLockPixelBuffer
        }
        defer { CVPixelBufferUnlockBaseAddress(cvPixelBuffer, .readOnly) }
        
        let yTexture = try createMTLTextureForPlane(
            cvPixelBuffer: cvPixelBuffer,
            planeIndex: 0,
            textureCache: cache,
            format: .r8Unorm,
            device: device
        )
        
        let uTexture = try createMTLTextureForPlane(
            cvPixelBuffer: cvPixelBuffer,
            planeIndex: 1,
            textureCache: cache,
            format: .r8Unorm,
            device: device
        )
        
        let vTexture = try createMTLTextureForPlane(
            cvPixelBuffer: cvPixelBuffer,
            planeIndex: 2,
            textureCache: cache,
            format: .r8Unorm,
            device: device
        )
        
        let rgbTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: CVPixelBufferGetWidth(cvPixelBuffer),
            height: CVPixelBufferGetHeight(cvPixelBuffer),
            mipmapped: false
        )
        rgbTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let rgbTexture = device.makeTexture(descriptor: rgbTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        if i420ToRgbKernelPipeline == nil {
            i420ToRgbKernelPipeline = try createComputePipeline(device: device, shaderName: "i420ToRgb")
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalScalingErrors.errorSettingUpEncoder
        }
        
        guard let i420ToRgbKernelPipeline else {
            throw MetalScalingErrors.failedToCreatePipeline
        }
        
        computeEncoder.setComputePipelineState(i420ToRgbKernelPipeline)
        computeEncoder.setTexture(yTexture, index: 0)
        computeEncoder.setTexture(uTexture, index: 1)
        computeEncoder.setTexture(vTexture, index: 2)
        computeEncoder.setTexture(rgbTexture, index: 3)
        
        let w = i420ToRgbKernelPipeline.threadExecutionWidth
        let h = max(1, i420ToRgbKernelPipeline.maxTotalThreadsPerThreadgroup / w)
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: rgbTexture.width, height: rgbTexture.height, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        defer {
            computeEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        return rgbTexture
    }
    
    public func createMTLTextureForPlane(
        cvPixelBuffer: CVPixelBuffer,
        planeIndex: Int,
        textureCache: CVMetalTextureCache,
        format: MTLPixelFormat,
        device: MTLDevice
    ) throws -> MTLTexture {
        // Create a Metal texture from the CVPixelBuffer plane
        let width = CVPixelBufferGetWidthOfPlane(cvPixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(cvPixelBuffer, planeIndex)
        
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            cvPixelBuffer,
            nil,
            format,
            width,
            height,
            planeIndex,
            &cvTexture) == kCVReturnSuccess else {
            throw MetalScalingErrors.failedToCreateTextureCacheFromImage
        }
        
        if let cvTexture = cvTexture, let metalTexture = CVMetalTextureGetTexture(cvTexture) {
            return metalTexture
        } else {
            throw MetalScalingErrors.failedToGetTexture
        }
    }
    
    // Converts an RGB CVPixelBuffer into an MTLTexture
    func createRGBMTLTexture(
        pixelBuffer: CVPixelBuffer,
        device: MTLDevice
    ) throws -> MTLTexture {
        let cache = self.textureCache
        
        // Lock the base address of the CVPixelBuffer
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) else {
            throw MetalScalingErrors.failedToLockPixelBuffer
        }
        
        defer {
            // Always unlock the CVPixelBuffer
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        
           // Ensure the PixelBuffer is in the correct format
           let format = MTLPixelFormat.bgra8Unorm
           guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
               throw NSError(domain: "Invalid pixel format for Metal texture", code: -1, userInfo: nil)
           }

           // Use the existing function but for the RGB plane (index 0)
           return try createMTLTextureForPlane(
               cvPixelBuffer: pixelBuffer,
               planeIndex: 0,  // RGB data is in a single plane
               textureCache: cache,
               format: format,
               device: device
           )
    }
    
    public func convertRGBToYUV(rgbTexture: MTLTexture) throws -> (yTexture: MTLTexture, uvTexture: MTLTexture) {
        // Create Metal textures for Y and UV planes
        let yTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: rgbTexture.width,
            height: rgbTexture.height,
            mipmapped: false)
        yTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let yTexture = device.makeTexture(descriptor: yTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        let uvTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Unorm,
            width: rgbTexture.width / 2,
            height: rgbTexture.height / 2,
            mipmapped: false)
        uvTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let uvTexture = device.makeTexture(descriptor: uvTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        // Create a Metal compute pipeline with a shader that converts RGB to YUV
        if rgbToYuvKernelPipeline == nil {
            rgbToYuvKernelPipeline = try createComputePipeline(device: device, shaderName: "rgbToYuv")
        }
        
        // Set up a command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalScalingErrors.errorSettingUpEncoder
        }
        
        guard let rgbToYuvKernelPipeline = rgbToYuvKernelPipeline else {
            throw MetalScalingErrors.failedToCreatePipeline
        }
        
        // Set textures and encode the compute shader
        computeEncoder.setComputePipelineState(rgbToYuvKernelPipeline)
        computeEncoder.setTexture(rgbTexture, index: 0)
        computeEncoder.setTexture(yTexture, index: 1)
        computeEncoder.setTexture(uvTexture, index: 2)
        
        let w = rgbToYuvKernelPipeline.threadExecutionWidth
        let h = max(1, rgbToYuvKernelPipeline.maxTotalThreadsPerThreadgroup / w)
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: rgbTexture.width, height: rgbTexture.height, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        defer {
            computeEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        return (yTexture, uvTexture)
    }
    
    func createComputePipeline(device: MTLDevice, shaderName: String) throws -> MTLComputePipelineState {
        guard let shaderFunction = library.makeFunction(name: shaderName) else {
            throw MetalScalingErrors.shaderFunctionNotFound
        }
        return try device.makeComputePipelineState(function: shaderFunction)
    }
    
    public struct ScaledInfo: Sendable {
        public var size: CGSize
        public var scaleX: CGFloat
        public var scaleY: CGFloat
        public init(size: CGSize, scaleX: CGFloat, scaleY: CGFloat) {
            self.size = size
            self.scaleX = scaleX
            self.scaleY = scaleY
        }
    }
    
    public func createSize(for scaleMode: ScaleMode = .none,
                           originalSize: CGSize,
                           desiredSize: CGSize,
                           aspectRatio: CGFloat = 0) -> ScaledInfo {
        var size = CGSize()
        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        switch scaleMode {
        case .aspectFitVertical:
            //This is correct for vertical, don't change it
            size.width = aspectRatio != 0 ? desiredSize.height * aspectRatio : desiredSize.width
            size.height = desiredSize.height
            
            if originalSize.width > originalSize.height {
                size.height = desiredSize.height
                if aspectRatio != 0 {
                    size.width = size.height * aspectRatio
                } else {
                    size.width = desiredSize.width
                }
            }
            
        case .aspectFitHorizontal:
            size.width = desiredSize.width
            size.height = aspectRatio != 0 ? desiredSize.width / aspectRatio : desiredSize.height
            
            // If fitting by width would overflow vertically (common for portrait video inside
            // landscape call tiles), clamp by height instead so the aspect ratio stays correct.
            if size.height > desiredSize.height {
                size.height = desiredSize.height
                if aspectRatio != 0 {
                    size.width = desiredSize.height * aspectRatio
                } else {
                    size.width = desiredSize.width
                }
            }
            
        case .aspectFill:
            let widthScale = desiredSize.width / max(originalSize.width, 1)
            let heightScale = desiredSize.height / max(originalSize.height, 1)
            let fillScale = max(widthScale, heightScale)
            size.width = originalSize.width * fillScale
            size.height = originalSize.height * fillScale
            
        case .none:
            size.width = originalSize.width
            size.height = originalSize.height
        }
        
        scaleX = originalSize.width > 0 ? size.width / originalSize.width : 1
        scaleY = originalSize.height > 0 ? size.height / originalSize.height : 1
        return ScaledInfo(size: size, scaleX: scaleX, scaleY: scaleY)
    }
    
    
    public func getAspectRatio(width: CGFloat, height: CGFloat) -> CGFloat {
        guard height != 0 else { return 0 }
        return width / height
    }

    let ciContext = CIContext(
        options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ]
    )
    
#if canImport(WebRTC)
    public func createMetalImage(
        fromPixelBuffer pixelBuffer: CVPixelBuffer? = nil,
        fromI420Buffer i420: RTCI420Buffer? = nil,
        parentBounds: CGSize,
        scaleInfo: ScaledInfo,
        aspectRatio: CGFloat
    ) async throws -> TextureInfo {
        if let pixelBuffer = pixelBuffer {
            var texture: MTLTexture!
            #if os(iOS)
            // Route iOS CVPixelBuffer conversion by concrete source format.
            // Remote fallback path feeds NV12 buffers here; use the Metal NV12 shader path directly.
            let pixelFormatType = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
            if pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                || pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || planeCount == 2 {
                texture = try convertYUVToRGB(
                    cvPixelBuffer: pixelBuffer,
                    device: self.device
                )
            } else if pixelFormatType == kCVPixelFormatType_420YpCbCr8Planar
                        || pixelFormatType == kCVPixelFormatType_420YpCbCr8PlanarFullRange
                        || planeCount == 3 {
                texture = try convertPlanar420ToRGB(
                    cvPixelBuffer: pixelBuffer,
                    device: self.device
                )
            } else if pixelFormatType == kCVPixelFormatType_32BGRA {
                texture = try createTexture(from: pixelBuffer, device: self.device)
            } else {
                // Keep CI as a compatibility fallback for uncommon formats.
                texture = try createTextureViaCoreImage(from: pixelBuffer)
            }
            if RemoteVideoTraceLogging.enabled, didLogIOSCVPixelBufferConversion == false {
                didLogIOSCVPixelBufferConversion = true
                let srcW = CVPixelBufferGetWidth(pixelBuffer)
                let srcH = CVPixelBufferGetHeight(pixelBuffer)
                let traceLine = "[MetalProcessor] iOS CV->Metal srcFormat=\(pixelFormatType) srcPlanes=\(planeCount) " +
                    "srcSize=\(srcW)x\(srcH) " +
                    "dstTextureFormat=\(texture.pixelFormat.rawValue) dstTextureSize=\(texture.width)x\(texture.height) " +
                    "parentBounds=\(parentBounds) scaleX=\(scaleInfo.scaleX) scaleY=\(scaleInfo.scaleY)"
                RemoteVideoTraceLogging.logger.log(
                    level: .trace,
                    message: Message(stringLiteral: traceLine)
                )
            }
            #else
            let pixelFormatType = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
            if pixelFormatType == kCVPixelFormatType_422YpCbCr8 {
                texture = try convert2VUYToRGB(
                    cvPixelBuffer: pixelBuffer,
                    device: self.device)
            } else if pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                        || pixelFormatType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                        || planeCount == 2 {
                texture = try convertYUVToRGB(
                    cvPixelBuffer: pixelBuffer,
                    device: self.device)
            } else if pixelFormatType == kCVPixelFormatType_420YpCbCr8Planar
                        || pixelFormatType == kCVPixelFormatType_420YpCbCr8PlanarFullRange
                        || planeCount == 3 {
                texture = try convertPlanar420ToRGB(
                    cvPixelBuffer: pixelBuffer,
                    device: self.device)
            } else if pixelFormatType == kCVPixelFormatType_32BGRA {
                texture = try createTexture(from: pixelBuffer, device: self.device)
            } else {
                throw NSError(
                    domain: "MetalProcessor",
                    code: Int(pixelFormatType),
                    userInfo: [
                        NSLocalizedDescriptionKey: "Unsupported CVPixelBuffer format \(pixelFormatType) with \(planeCount) planes"
                    ]
                )
            }
            #endif
            
            let resizedTexture = try resizeImage(
                sourceTexture: texture,
                parentBounds: parentBounds,
                scaleInfo: scaleInfo,
                aspectRatio: aspectRatio)
            var info = try getTextureInfo(texture: resizedTexture)
            info.scaleX = scaleInfo.scaleX
            info.scaleY = scaleInfo.scaleY
            return info
        } else if let i420 = i420 {
            let texture = try createi420Texture(from: i420, device: self.device)
            let resizedTexture = try resizeImage(
                sourceTexture: texture,
                parentBounds: parentBounds,
                scaleInfo: scaleInfo,
                aspectRatio: aspectRatio
            )
            var info = try getTextureInfo(texture: resizedTexture)
            info.scaleX = scaleInfo.scaleX
            info.scaleY = scaleInfo.scaleY
            return info
        } else {
            throw MetalScalingErrors.failedToCreateTexture
        }
    }
#endif
    
    public func resizeImage(
        sourceTexture: MTLTexture,
        parentBounds: CGSize,
        scaleInfo: ScaledInfo,
        aspectRatio: CGFloat
    ) throws -> MTLTexture {
        
        let filter = MPSImageLanczosScale(device: device)
        
        // DESTINATION NEEDS TO BE SIZE OF PARENT VIEW (Metal rejects 0×0 descriptors).
        let destW = max(1, Int(ceil(parentBounds.width)))
        let destH = max(1, Int(ceil(parentBounds.height)))
        let destTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sourceTexture.pixelFormat,
                                                                             width: destW,
                                                                             height: destH,
                                                                             mipmapped: false)
        destTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let destTexture = device.makeTexture(descriptor: destTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        
        let translateX = (Double(destTextureDescriptor.width) - Double(sourceTexture.width) * scaleInfo.scaleX) / 2
        let translateY = (Double(destTextureDescriptor.height) - Double(sourceTexture.height) * scaleInfo.scaleY) / 2
        
        var transform = MPSScaleTransform(
            scaleX: scaleInfo.scaleX,
            scaleY: scaleInfo.scaleY,
            translateX: translateX,
            translateY: translateY
        )
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw MetalScalingErrors.errorSettingUpCommandQueue }
        withUnsafePointer(to: &transform) { transformPtr in
            filter.scaleTransform = transformPtr
        filter.encode(commandBuffer: commandBuffer,
                      sourceTexture: sourceTexture,
                      destinationTexture: destTexture)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return destTexture
    }
    
    private func getTextureInfo(texture: MTLTexture) throws -> TextureInfo {
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: texture.width, height: texture.height, depth: 1))
        let bytesPerRow = texture.width * 4
        let imageByteCount = bytesPerRow * texture.height
        
        var bytes = [UInt8](repeating: 0, count: imageByteCount)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        guard let provider = CGDataProvider(data: NSData(bytes: &bytes, length: bytes.count * MemoryLayout<UInt8>.size)) else {
            throw MetalScalingErrors.failedToCreateDataProvider
        }
        
        return TextureInfo(
            texture: texture,
            bytesPerRow: bytesPerRow,
            bitmapInfo: texture.bitmapInfo,
            provider: provider
        )
    }
    
    public func mirrorTexture(
        sourceTexture: MTLTexture,
        horizontal: Bool = true,
        vertical: Bool = false
    ) throws -> TextureInfo {
        // Reuse Texture Descriptor
        let destinationDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sourceTexture.pixelFormat,
                                                                             width: sourceTexture.width,
                                                                             height: sourceTexture.height,
                                                                             mipmapped: false)
        destinationDescriptor.usage = [.shaderRead, .shaderWrite]
        
        // Create Destination Texture
        guard let destinationTexture = device.makeTexture(descriptor: destinationDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        // Create Compute Pipeline (Assuming it's created once and reused)
        if flipKernelPipeline == nil {
            flipKernelPipeline = try createComputePipeline(device: device, shaderName: "flipKernel")
        }
        
        // Create Command Buffer and Encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalScalingErrors.errorSettingUpEncoder
        }
        
        guard let flipKernelPipeline = flipKernelPipeline else {
            throw MetalScalingErrors.failedToCreatePipeline
        }
        // Set Compute Pipeline State
        computeEncoder.setComputePipelineState(flipKernelPipeline)
        
        var horizontal = horizontal
        var vertical = vertical
        // Set Compute Encoder Parameters
        computeEncoder.setBytes(&horizontal, length: MemoryLayout<Bool>.size, index: 0)
        computeEncoder.setBytes(&vertical, length: MemoryLayout<Bool>.size, index: 1)
        
        // Set Source and Destination Textures
        computeEncoder.setTexture(sourceTexture, index: 0)
        computeEncoder.setTexture(destinationTexture, index: 1)
        
        // Calculate Threadgroup Size and Dispatch Compute Work
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupCount = MTLSize(width: (destinationTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
                                       height: (destinationTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
                                       depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        defer {
            computeEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        // Return Destination Texture
        return try getTextureInfo(texture: destinationTexture)
    }
    
    public func blurTexture(sourceTexture: MTLTexture) async throws -> MTLTexture? {
        let filter = MPSImageGaussianBlur(device: device, sigma: 10)
        
        //DESTINATION NEEDS TO BE SIZE OF PARENT VIEW
        let destTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sourceTexture.pixelFormat,
                                                                             width: Int(sourceTexture.width),
                                                                             height: Int(sourceTexture.height),
                                                                             mipmapped: false)
        destTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let destTexture = device.makeTexture(descriptor: destTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw MetalScalingErrors.errorSettingUpCommandQueue }

        filter.encode(commandBuffer: commandBuffer,
                      sourceTexture: sourceTexture,
                      destinationTexture: destTexture)
        
        commandBuffer.commit()
        await commandBuffer.completed()
        
        return destTexture
    }
    
#if os(iOS)
    public func createImage(from texture: MTLTexture, colorSpace: [CIImageOption: Any] = [CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB()]) async -> UIImage {
        guard let ciImage = CIImage(mtlTexture: texture, options: colorSpace) else { fatalError("Failed to create CIImage") }
        let orientedImage = ciImage.oriented(forExifOrientation: 4)
        return UIImage(ciImage: orientedImage)
    }
#elseif os(macOS)
    
    public func resizeAndConvertToNSImage(image: NSImage,
                                          desiredSize: CGSize) async throws -> NSImage {
        let imageTexture = try await resizeImage(
            image: image,
            desiredSize: desiredSize)
        return await createImage(from: imageTexture)
    }
    
    public func createImage(from texture: MTLTexture, colorSpace: [CIImageOption: Any] = [CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB()]) async -> NSImage {
        guard let ciImage = CIImage(mtlTexture: texture, options: colorSpace) else { fatalError("Failed to create CIImage") }
        let orientedImage = ciImage.oriented(forExifOrientation: 4)
        // Reuse the actor-scoped CIContext (cheaper than creating per call).
        guard let cgImage = self.ciContext.createCGImage(orientedImage, from: orientedImage.extent) else {
            fatalError("Failed to create CGImage")
        }
        
        // Create and return an NSImage from the CGImage
        return NSImage(cgImage: cgImage, size: orientedImage.extent.size)
    }
#endif
}

extension MetalProcessor {
    public func convertYuvTextureToPixelBuffer(
        y: MTLTexture,
        uv: MTLTexture,
        attachments: CMAttachmentBearerAttachments
    ) throws -> CVPixelBuffer? {
        let pool = try pixelBufferPool(
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            width: y.width,
            height: y.height,
            metalCompatible: true
        )
        
        // Create output pixel buffer
        var outputPixelBuffer: CVPixelBuffer?
        let status2 = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer)
        guard status2 == kCVReturnSuccess, let pixelBuffer = outputPixelBuffer else {
            throw MetalScalingErrors.failedToCreateOutputPixelBuffer
        }
        
        // Lock the base address of the output CVPixelBuffer
        _ = CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        // Copy Y and UV plane data
        if let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
           let uvBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
            
            let yDestination = yBaseAddress.assumingMemoryBound(to: UInt8.self)
            let uvDestination = uvBaseAddress.assumingMemoryBound(to: UInt8.self)
            
            // Copy Y plane data
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yRegion = MTLRegionMake2D(0, 0, y.width, y.height)
            y.getBytes(yDestination, bytesPerRow: yBytesPerRow, from: yRegion, mipmapLevel: 0)
            
            // Copy UV plane data
            let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let uvRegion = MTLRegionMake2D(0, 0, uv.width, uv.height)
            uv.getBytes(uvDestination, bytesPerRow: uvBytesPerRow, from: uvRegion, mipmapLevel: 0)
        }
        // Unlock base addresses
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        CMSetAttachments(pixelBuffer, attachments: attachments.propagated as CFDictionary, attachmentMode: kCMAttachmentMode_ShouldPropagate)
        CMSetAttachments(pixelBuffer, attachments: attachments.nonPropagated as CFDictionary, attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
        return pixelBuffer
    }
    
    
    ///Converts a YUV PixelBuffer to a YUV Texture and then outputs a new CVPixelBuffer from that YUV Texture that is properly formated.
    public func convertToPixelBuffer(
        cvPixelBuffer: CVPixelBuffer,
        parentBounds: CGSize,
        scaleInfo: ScaledInfo,
        aspectRatio: CGFloat
    ) throws -> CVPixelBuffer? {
        let width = Int(parentBounds.width)
        let height = Int(parentBounds.height)
        let pool = try pixelBufferPool(
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            width: width,
            height: height,
            metalCompatible: false
        )
        
        // Use actor-scoped cache (cheaper than creating per call).
        let cache = self.textureCache
        
        // Lock the base address of the input CVPixelBuffer
       _ = CVPixelBufferLockBaseAddress(cvPixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(cvPixelBuffer, .readOnly) }
        
        // Create textures for Y and UV planes
        let yTexture = try createMTLTextureForPlane(cvPixelBuffer: cvPixelBuffer, planeIndex: 0, textureCache: cache, format: .r8Unorm, device: device)
        let uvTexture = try createMTLTextureForPlane(cvPixelBuffer: cvPixelBuffer, planeIndex: 1, textureCache: cache, format: .rg8Unorm, device: device)
        
        // Create output pixel buffer
        var outputPixelBuffer: CVPixelBuffer?
        let status2 = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer)
        guard status2 == kCVReturnSuccess, let pixelBuffer = outputPixelBuffer else {
            throw MetalScalingErrors.failedToCreateOutputPixelBuffer
        }
        
        // Lock the base address of the output CVPixelBuffer
        _ = CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        // Copy Y and UV plane data
        if let yBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
           let uvBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
            
            let yDestination = yBaseAddress.assumingMemoryBound(to: UInt8.self)
            let uvDestination = uvBaseAddress.assumingMemoryBound(to: UInt8.self)
            
            // Copy Y plane data
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yRegion = MTLRegionMake2D(0, 0, yTexture.width, yTexture.height)
            yTexture.getBytes(yDestination, bytesPerRow: yBytesPerRow, from: yRegion, mipmapLevel: 0)
            
            // Copy UV plane data
            let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let uvRegion = MTLRegionMake2D(0, 0, uvTexture.width, uvTexture.height)
            uvTexture.getBytes(uvDestination, bytesPerRow: uvBytesPerRow, from: uvRegion, mipmapLevel: 0)
        }
        
        // Unlock base addresses
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
    
    
    public func createSampleBuffer(_ pixelBuffer: CVPixelBuffer, time: CMTime) async throws -> CMSampleBuffer? {
        // Create the Format Description for the Image Buffer
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                                  imageBuffer: pixelBuffer,
                                                                  formatDescriptionOut: &formatDescription)
        guard status == noErr, let formatDesc = formatDescription else {
            throw MetalScalingErrors.sampleBufferCreationError
        }
        
        // Create Sample Timing Info
        var sampleTimingInfo = CMSampleTimingInfo(duration: .invalid,
                                                  presentationTimeStamp: time,
                                                  decodeTimeStamp: .invalid)
        
        // Create the Sample Buffer
        var sampleBuffer: CMSampleBuffer?
        let status2 = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                               imageBuffer: pixelBuffer,
                                                               formatDescription: formatDesc,
                                                               sampleTiming: &sampleTimingInfo,
                                                               sampleBufferOut: &sampleBuffer)
        guard status2 == noErr, let buffer = sampleBuffer else {
            throw MetalScalingErrors.sampleBufferCreationError
        }
        
        return buffer
    }
    
    
    public func createPixelBuffer(ciImage: CIImage, ciContext: CIContext) -> CVPixelBuffer? {
        let width = Int(ciImage.extent.width.rounded(.down))
        let height = Int(ciImage.extent.height.rounded(.down))
        do {
            let pool = try pixelBufferPool(
                pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                width: width,
                height: height,
                metalCompatible: true
            )
        var pixelBuffer: CVPixelBuffer?
            let poolStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard let unwrapped = pixelBuffer, poolStatus == kCVReturnSuccess else {
            print("Failed to create pixel buffer from pool. Status: \(poolStatus)")
            return nil
        }
        let orientedImage = ciImage.oriented(forExifOrientation: 4)
            ciContext.render(orientedImage, to: unwrapped)
            return unwrapped
        } catch {
            print("Failed to create pixel buffer pool: \(error)")
            return nil
        }
    }
}

#if canImport(WebRTC)
@preconcurrency import WebRTC
//MARK: I420
extension MetalProcessor  {
    
    public struct I420Textures: Sendable {
        public var yTexture: MTLTexture
        public var uTexture: MTLTexture
        public var vTexture: MTLTexture
        public init(yTexture: MTLTexture, uTexture: MTLTexture, vTexture: MTLTexture) {
            self.yTexture = yTexture
            self.uTexture = uTexture
            self.vTexture = vTexture
        }
    }
    
    private func makeNV12PixelBufferFromI420(_ i420Buffer: RTCI420Buffer) throws -> CVPixelBuffer {
        let width = Int(i420Buffer.width)
        let height = Int(i420Buffer.height)
        
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw MetalScalingErrors.failedToCreateOutputPixelBuffer
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        guard let yDestBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvDestBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            throw MetalScalingErrors.failedToCreateOutputPixelBuffer
        }
        
        let yDestStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvDestStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        
        let ySrcStride = Int(i420Buffer.strideY)
        for row in 0..<height {
            let src = i420Buffer.dataY.advanced(by: row * ySrcStride)
            let dst = yDestBase.advanced(by: row * yDestStride)
            memcpy(dst, src, width)
        }
        
        let chromaWidth = (width + 1) / 2
        let chromaHeight = (height + 1) / 2
        let uSrcStride = Int(i420Buffer.strideU)
        let vSrcStride = Int(i420Buffer.strideV)
        
        for row in 0..<chromaHeight {
            let uSrc = i420Buffer.dataU.advanced(by: row * uSrcStride)
            let vSrc = i420Buffer.dataV.advanced(by: row * vSrcStride)
            let uvDst = uvDestBase.advanced(by: row * uvDestStride).assumingMemoryBound(to: UInt8.self)
            for col in 0..<chromaWidth {
                uvDst[col * 2] = uSrc[col]
                uvDst[col * 2 + 1] = vSrc[col]
            }
        }
        
        return pixelBuffer
    }
    
    private func createTextureFromI420ViaCoreImage(_ i420Buffer: RTCI420Buffer) throws -> MTLTexture {
        let pixelBuffer = try makeNV12PixelBufferFromI420(i420Buffer)
        return try createTextureViaCoreImage(from: pixelBuffer)
    }
    
    public func createi420Texture(from i420Buffer: RTCI420Buffer, device: MTLDevice) throws -> MTLTexture {
        #if os(iOS)
        let yPlane = i420Buffer.dataY
        let uPlane = i420Buffer.dataU
        let vPlane = i420Buffer.dataV
        
        let textures = try createMetalTexturesFromYUVPlanes(
            yData: yPlane,
            uData: uPlane,
            vData: vPlane,
            yStride: Int(i420Buffer.strideY),
            uStride: Int(i420Buffer.strideU),
            vStride: Int(i420Buffer.strideV),
            width: Int(i420Buffer.width),
            height: Int(i420Buffer.height),
            device: device
        )
        let rgbTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(i420Buffer.width),
            height: Int(i420Buffer.height),
            mipmapped: false
        )
        rgbTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let rgbTexture = device.makeTexture(descriptor: rgbTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        if i420ToRgbKernelPipeline == nil {
            i420ToRgbKernelPipeline = try createComputePipeline(device: device, shaderName: "i420ToRgb")
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalScalingErrors.errorSettingUpEncoder
        }
        guard let i420ToRgbKernelPipeline = i420ToRgbKernelPipeline else {
            throw MetalScalingErrors.failedToCreatePipeline
        }
        computeEncoder.setComputePipelineState(i420ToRgbKernelPipeline)
        computeEncoder.setTexture(textures.yTexture, index: 0)
        computeEncoder.setTexture(textures.uTexture, index: 1)
        computeEncoder.setTexture(textures.vTexture, index: 2)
        computeEncoder.setTexture(rgbTexture, index: 3)
        
        let w = i420ToRgbKernelPipeline.threadExecutionWidth
        let h = max(1, i420ToRgbKernelPipeline.maxTotalThreadsPerThreadgroup / w)
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: rgbTexture.width, height: rgbTexture.height, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        if RemoteVideoTraceLogging.enabled, didLogIOSI420Conversion == false {
            didLogIOSI420Conversion = true
            let traceLine = "[MetalProcessor] iOS I420->Metal srcSize=\(i420Buffer.width)x\(i420Buffer.height) " +
                "srcStrides(y/u/v)=\(i420Buffer.strideY)/\(i420Buffer.strideU)/\(i420Buffer.strideV) " +
                "dstTextureFormat=\(rgbTexture.pixelFormat.rawValue) dstTextureSize=\(rgbTexture.width)x\(rgbTexture.height)"
            RemoteVideoTraceLogging.logger.log(
                level: .trace,
                message: Message(stringLiteral: traceLine)
            )
        }
        defer {
            computeEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        return rgbTexture
        #else
        let yPlane = i420Buffer.dataY
        let uPlane = i420Buffer.dataU
        let vPlane = i420Buffer.dataV
        
        let textures = try createMetalTexturesFromYUVPlanes(
            yData: yPlane,
            uData: uPlane,
            vData: vPlane,
            yStride: Int(i420Buffer.strideY),
            uStride: Int(i420Buffer.strideU),
            vStride: Int(i420Buffer.strideV),
            width: Int(i420Buffer.width),
            height: Int(i420Buffer.height),
            device: device)
        // Create a Metal texture for RGB output
        let rgbTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(i420Buffer.width),
            height: Int(i420Buffer.height),
            mipmapped: false)
        rgbTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let rgbTexture = device.makeTexture(descriptor: rgbTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        // Create a Metal compute pipeline with a shader that converts YUV to RGB
        if i420ToRgbKernelPipeline == nil {
            i420ToRgbKernelPipeline = try createComputePipeline(device: device, shaderName: "i420ToRgb")
        }
        // Set up a command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalScalingErrors.errorSettingUpEncoder
        }
        
        guard let i420ToRgbKernelPipeline = i420ToRgbKernelPipeline else {
            throw MetalScalingErrors.failedToCreatePipeline
        }
        // Set textures and encode the compute shader
        computeEncoder.setComputePipelineState(i420ToRgbKernelPipeline)
        computeEncoder.setTexture(textures.yTexture, index: 0)
        computeEncoder.setTexture(textures.uTexture, index: 1)
        computeEncoder.setTexture(textures.vTexture, index: 2)
        computeEncoder.setTexture(rgbTexture, index: 3)
        
        let w = i420ToRgbKernelPipeline.threadExecutionWidth
        let h = max(1, i420ToRgbKernelPipeline.maxTotalThreadsPerThreadgroup / w)
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: rgbTexture.width, height: rgbTexture.height, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        defer {
            computeEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        return rgbTexture
        #endif
    }
    
    public func createMetalTexturesFromYUVPlanes(
        yData: UnsafePointer<UInt8>,
        uData: UnsafePointer<UInt8>,
        vData: UnsafePointer<UInt8>,
        yStride: Int,
        uStride: Int,
        vStride: Int,
        width: Int,
        height: Int,
        device: MTLDevice
    ) throws -> I420Textures {
        
        let chromaWidth = (width + 1) / 2
        let chromaHeight = (height + 1) / 2
        let bytesPerRowY = max(1, yStride)
        let bytesPerRowU = max(1, uStride)
        let bytesPerRowV = max(1, vStride)

        if RemoteVideoTraceLogging.enabled, i420PlaneUploadLogCount < 10 {
            i420PlaneUploadLogCount += 1
            let rowSampleY = describePlaneRows(ptr: yData, stride: bytesPerRowY, rowCount: height, logicalWidth: width)
            let rowSampleU = describePlaneRows(ptr: uData, stride: bytesPerRowU, rowCount: chromaHeight, logicalWidth: chromaWidth)
            let rowSampleV = describePlaneRows(ptr: vData, stride: bytesPerRowV, rowCount: chromaHeight, logicalWidth: chromaWidth)
            let traceLine = "[MetalProcessor] I420 upload #\(i420PlaneUploadLogCount) " +
                "size=\(width)x\(height) chroma=\(chromaWidth)x\(chromaHeight) " +
                "strides(y/u/v)=\(yStride)/\(uStride)/\(vStride) " +
                "expected(y/u/v)=\(width)/\(chromaWidth)/\(chromaWidth) " +
                "rowSampleY=\(rowSampleY) rowSampleU=\(rowSampleU) rowSampleV=\(rowSampleV)"
            RemoteVideoTraceLogging.logger.log(
                level: .trace,
                message: Message(stringLiteral: traceLine)
            )
        }
        
        // Create Metal texture for Y component (luminance)
        let textureDescriptorY = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptorY.usage = [.shaderRead, .shaderWrite]
        
        guard let yTexture = device.makeTexture(descriptor: textureDescriptorY) else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        
        let regionY = MTLRegionMake2D(0, 0, width, height)
        yTexture.replace(region: regionY, mipmapLevel: 0, withBytes: yData, bytesPerRow: bytesPerRowY)
        
        // Create Metal texture for U component (chrominance)
        let textureDescriptorU = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: chromaWidth, height: chromaHeight, mipmapped: false)
        textureDescriptorU.usage = [.shaderRead, .shaderWrite]
        
        guard let uTexture = device.makeTexture(descriptor: textureDescriptorU) else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        
        let regionU = MTLRegionMake2D(0, 0, chromaWidth, chromaHeight)
        uTexture.replace(region: regionU, mipmapLevel: 0, withBytes: uData, bytesPerRow: bytesPerRowU)
        
        // Create Metal texture for V component (chrominance)
        let textureDescriptorV = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: chromaWidth, height: chromaHeight, mipmapped: false)
        textureDescriptorV.usage = [.shaderRead, .shaderWrite]
        
        guard let vTexture = device.makeTexture(descriptor: textureDescriptorV) else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        
        let regionV = MTLRegionMake2D(0, 0, chromaWidth, chromaHeight)
        vTexture.replace(region: regionV, mipmapLevel: 0, withBytes: vData, bytesPerRow: bytesPerRowV)
        
        return I420Textures(
            yTexture: yTexture,
            uTexture: uTexture,
            vTexture: vTexture)
    }

    private func describePlaneRows(
        ptr: UnsafePointer<UInt8>,
        stride: Int,
        rowCount: Int,
        logicalWidth: Int
    ) -> String {
        guard rowCount > 0, stride > 0, logicalWidth > 0 else { return "none" }
        let rows = [0, rowCount / 2, max(0, rowCount - 1)]
        var out: [String] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            let rowPtr = ptr.advanced(by: row * stride)
            let previewCount = min(8, logicalWidth)
            let preview = previewRowBytes(rowPtr, count: previewCount)
            let stats = sampleStats(rowPtr, count: min(logicalWidth, 64))
            out.append("r\(row):\(preview) s=\(stats.min)/\(stats.max)/\(stats.avg)")
        }
        return out.joined(separator: " | ")
    }

    private func previewRowBytes(_ ptr: UnsafePointer<UInt8>, count: Int) -> String {
        guard count > 0 else { return "[]" }
        var values: [String] = []
        values.reserveCapacity(count)
        for i in 0..<count {
            values.append(String(format: "%02x", ptr[i]))
        }
        return "[" + values.joined(separator: " ") + "]"
    }

    private func sampleStats(_ ptr: UnsafePointer<UInt8>, count: Int) -> (min: Int, max: Int, avg: Int) {
        guard count > 0 else { return (0, 0, 0) }
        var lo = Int.max
        var hi = Int.min
        var sum = 0
        for i in 0..<count {
            let value = Int(ptr[i])
            lo = min(lo, value)
            hi = max(hi, value)
            sum += value
        }
        return (lo, hi, sum / count)
    }
    
}
#endif

extension MetalProcessor {
    private func getTextureInfo(
        texture: MTLTexture,
        imageSize: CGSize,
        bitsPerPixel: Int,
        bitmapInfo: CGBitmapInfo
    ) throws -> TextureInfo {
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: texture.width, height: texture.height, depth: 1))
        let bytesPerRow = texture.width * 4
        let imageByteCount = bytesPerRow * texture.height
        
        var bytes = [UInt8](repeating: 0, count: imageByteCount)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        guard let provider = CGDataProvider(data: NSData(bytes: &bytes, length: bytes.count * MemoryLayout<UInt8>.size)) else {
            throw MetalScalingErrors.failedToCreateDataProvider
        }
        
        return TextureInfo(
            texture: texture,
            bytesPerRow: bytesPerRow,
            bitmapInfo: bitmapInfo,
            provider: provider
        )
    }
    
#if os(iOS)
    private func createTexture(fromImage: UIImage, device: MTLDevice) -> MTLTexture? {
        guard let cgImage = fromImage.cgImage else {
            print("Error: UIImage is nil or cannot be converted to CGImage.")
            return nil
        }
        let textureLoader = MTKTextureLoader(device: device)
        do {
            let texture = try textureLoader.newTexture(cgImage: cgImage, options: nil)
            return texture
        } catch {
            print("Error creating texture from image: \(error.localizedDescription)")
            return nil
        }
    }

    public func resizeImage(
        image: UIImage,
        parentBounds: CGSize,
        scaleInfo: ScaledInfo,
        aspectRatio: CGFloat) async throws -> TextureInfo {
        
            guard let texture = createTexture(fromImage: image, device: device) else {
                throw MetalScalingErrors.failedToCreateTexture
            }
            let resizedTexture = try resizeImage(
                sourceTexture: texture,
                parentBounds: parentBounds,
                scaleInfo: scaleInfo,
                aspectRatio: aspectRatio
            )
            let imageSize = CGSize(width: resizedTexture.width, height: resizedTexture.height)
            var destinationTextureInfo = try getTextureInfo(
                texture: resizedTexture,
                imageSize: imageSize,
                bitsPerPixel: image.bitsPerPixel,
                bitmapInfo: image.bitmapInfo)
            
            destinationTextureInfo.bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            destinationTextureInfo.scaleX = scaleInfo.scaleX
            destinationTextureInfo.scaleY = scaleInfo.scaleY
            return destinationTextureInfo
        }
    
    public func resizeImage(
        image: UIImage,
        desiredSize: CGSize
    ) async throws -> MTLTexture {
        let originalSize = image.size
        let aspectRatio = await getAspectRatio(width: originalSize.width, height: originalSize.height)
        let info = await createSize(for: .aspectFill, originalSize: originalSize, desiredSize: desiredSize, aspectRatio: aspectRatio)
        let textureInfo = try await resizeImage(
            image: image,
            parentBounds: info.size,
            scaleInfo: info,
            aspectRatio: aspectRatio
        )
        return textureInfo.texture
    }
#elseif os(macOS)
    private func createTexture(fromImage: NSImage, device: MTLDevice) -> MTLTexture? {
        guard let cgImage = fromImage.cgImage else {
            return nil
        }
        
        let textureLoader = MTKTextureLoader(device: device)
        do {
            let texture = try textureLoader.newTexture(cgImage: cgImage, options: nil)
            return texture
        } catch {
            print("Error creating texture from image: \(error.localizedDescription)")
            return nil
        }
    }
    
    public func resizeImage(
        image: NSImage,
        parentBounds: CGSize,
        scaleInfo: ScaledInfo,
        aspectRatio: CGFloat) async throws -> TextureInfo {
            
            guard let texture = createTexture(fromImage: image, device: device) else {
                throw MetalScalingErrors.failedToCreateTexture
            }
            let resizedTexture = try resizeImage(
                sourceTexture: texture,
                parentBounds: parentBounds,
                scaleInfo: scaleInfo,
                aspectRatio: aspectRatio
            )
            let imageSize = CGSize(width: resizedTexture.width, height: resizedTexture.height)
            var destinationTextureInfo = try getTextureInfo(
                texture: resizedTexture,
                imageSize: imageSize,
                bitsPerPixel: image.bitsPerPixel!,
                bitmapInfo: image.bitmapInfo!.1)
            
            destinationTextureInfo.bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            destinationTextureInfo.scaleX = scaleInfo.scaleX
            destinationTextureInfo.scaleY = scaleInfo.scaleY
            return destinationTextureInfo
        }
    
    public func resizeImage(
        image: NSImage,
        desiredSize: CGSize
    ) async throws -> MTLTexture {
        let originalSize = image.size
        let aspectRatio = getAspectRatio(width: originalSize.width, height: originalSize.height)
        let info = createSize(for: .aspectFill, originalSize: originalSize, desiredSize: desiredSize, aspectRatio: aspectRatio)
        let textureInfo = try await resizeImage(
            image: image,
            parentBounds: info.size,
            scaleInfo: info,
            aspectRatio: aspectRatio
        )
        return textureInfo.texture
    }
#endif
}

// MARK: - Virtual Background (iOS)
#if os(iOS) && canImport(UIKit) && canImport(Vision) && canImport(CoreImage)
extension MetalProcessor {
    
    /// High-level virtual background options.
    @available(iOS 15.0, *)
    public enum VirtualBackground {
        case none
        case blur(sigma: Double)
        case image(UIImage)
    }
    
    // Stored on the actor for concurrency-safety and reuse. Vision request objects are not Sendable.
    @available(iOS 15.0, *)
    private var segmentationRequest: VNGeneratePersonSegmentationRequest {
        if let existing = personSegmentationRequest { return existing }
        let req = VNGeneratePersonSegmentationRequest()
        req.qualityLevel = .balanced
        // Accurate mask values; caller can smooth downstream if desired.
        req.outputPixelFormat = kCVPixelFormatType_OneComponent8
        personSegmentationRequest = req
        return req
    }
    
    /// World-class, self-contained virtual background pipeline:
    /// - Runs Vision person segmentation on the foreground frame
    /// - Composites the requested background via Core Image
    /// - Renders to a Metal-compatible pixel buffer and returns an `MTLTexture`
    @available(iOS 15.0, *)
    public func applyVirtualBackground(
        foregroundPixelBuffer: CVPixelBuffer,
        background: VirtualBackground,
        orientation: CGImagePropertyOrientation = .up,
        outputSize: CGSize? = nil,
        scaleMode: ScaleMode = .aspectFill
    ) async throws -> MTLTexture {
        return try await applyVirtualBackgroundWithPixelBuffer(
            foregroundPixelBuffer: foregroundPixelBuffer,
            background: background,
            orientation: orientation,
            outputSize: outputSize,
            scaleMode: scaleMode
        ).texture
    }
    
    /// Same pipeline as `applyVirtualBackground(...)` but also returns the rendered CVPixelBuffer
    /// (useful when you need both Metal + non-Metal consumers).
    @available(iOS 15.0, *)
    public func applyVirtualBackgroundWithPixelBuffer(
        foregroundPixelBuffer: CVPixelBuffer,
        background: VirtualBackground,
        orientation: CGImagePropertyOrientation = .up,
        outputSize: CGSize? = nil,
        scaleMode: ScaleMode = .aspectFill
    ) async throws -> (texture: MTLTexture, pixelBuffer: CVPixelBuffer) {
        // 1) Build foreground CIImage
        let foregroundCI = CIImage(cvPixelBuffer: foregroundPixelBuffer).oriented(orientation)
        
        // 2) Run Vision segmentation (synchronously on the MetalProcessor actor thread).
        let handler = VNImageRequestHandler(
            cvPixelBuffer: foregroundPixelBuffer,
            orientation: orientation,
            options: [:]
        )
        let request = segmentationRequest
        try handler.perform([request])
        guard let mask = request.results?.first else {
            throw MetalScalingErrors.cannotProcessBackgroundImage
        }
        
        // Vision mask is typically lower-res; scale to foreground extent.
        var maskCI = CIImage(cvPixelBuffer: mask.pixelBuffer)
        let sx = foregroundCI.extent.width / maskCI.extent.width
        let sy = foregroundCI.extent.height / maskCI.extent.height
        maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy)).cropped(to: foregroundCI.extent)
        
        // 3) Create background CIImage
        let backgroundCI: CIImage = {
            switch background {
            case .none:
                return foregroundCI
            case .blur(let sigma):
                return foregroundCI
                    .clampedToExtent()
                    .applyingGaussianBlur(sigma: sigma)
                    .cropped(to: foregroundCI.extent)
            case .image(let uiImage):
                guard let bg = CIImage(image: uiImage) else { return foregroundCI }
                // Aspect-fill to match the foreground extent.
                let bgAR = bg.extent.width / max(bg.extent.height, 1)
                let fgAR = foregroundCI.extent.width / max(foregroundCI.extent.height, 1)
                let scale: CGFloat = (bgAR > fgAR)
                    ? foregroundCI.extent.height / bg.extent.height
                    : foregroundCI.extent.width / bg.extent.width
                let scaled = bg.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let x = scaled.extent.midX - foregroundCI.extent.midX
                let y = scaled.extent.midY - foregroundCI.extent.midY
                return scaled.transformed(by: CGAffineTransform(translationX: -x, y: -y)).cropped(to: foregroundCI.extent)
            }
        }()
        
        // 4) Composite
        let blend = CIFilter.blendWithMask()
        blend.inputImage = foregroundCI
        blend.backgroundImage = backgroundCI
        blend.maskImage = maskCI
        guard var outputCI = blend.outputImage?.cropped(to: foregroundCI.extent) else {
            throw MetalScalingErrors.imageCreationFailed
        }
        
        // 5) Optional output sizing (keeps caller API simple)
        if let outputSize, outputSize.width > 0, outputSize.height > 0 {
            let aspect = getAspectRatio(width: foregroundCI.extent.width, height: foregroundCI.extent.height)
            let scaled = createSize(for: scaleMode, originalSize: foregroundCI.extent.size, desiredSize: outputSize, aspectRatio: aspect)
            let sx = scaled.size.width / foregroundCI.extent.width
            let sy = scaled.size.height / foregroundCI.extent.height
            outputCI = outputCI
                .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                .cropped(to: CGRect(origin: .zero, size: scaled.size))
        }
        
        // 6) Render into a Metal-compatible BGRA pixel buffer and create a texture view
        let width = Int(outputCI.extent.width.rounded(.down))
        let height = Int(outputCI.extent.height.rounded(.down))
        let pool = try pixelBufferPool(
            pixelFormat: kCVPixelFormatType_32BGRA,
            width: width,
            height: height,
            metalCompatible: true
        )
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let pixelBuffer = pb else {
            throw MetalScalingErrors.failedToCreateOutputPixelBuffer
        }
        ciContext.render(outputCI, to: pixelBuffer)
        
        let texture = try createRGBMTLTexture(pixelBuffer: pixelBuffer, device: device)
        return (texture: texture, pixelBuffer: pixelBuffer)
    }
}
#endif


public struct TextureInfo: Sendable {
    public var texture: MTLTexture
    public var bytesPerRow: Int
    public var bitmapInfo: CGBitmapInfo
    public var provider: CGDataProvider
    public var time: CMTime?
    public var scaleX: CGFloat?
    public var scaleY: CGFloat?
}

extension CVPixelBuffer {
    var bitsPerPixel: Int {
        let pixelFormat = CVPixelBufferGetPixelFormatType(self)
        var bitsPerPixel = 0
        switch pixelFormat {
        case kCVPixelFormatType_24RGB:
            bitsPerPixel = 24 // 8 bits per channel (R, G, B)
        case kCVPixelFormatType_32ARGB, kCVPixelFormatType_32BGRA, kCVPixelFormatType_32RGBA:
            bitsPerPixel = 32 // 8 bits per channel (R, G, B, A)
        case kCVPixelFormatType_16LE555, kCVPixelFormatType_16LE5551, kCVPixelFormatType_16LE565, kCVPixelFormatType_422YpCbCr8, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            bitsPerPixel = 16 // 5 bits for R, G, B (and optionally 1 bit for A)
        case kCVPixelFormatType_420YpCbCr8Planar, kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            bitsPerPixel = 12 // Planar YUV with 8 bits for Y (luma), and 8 bits for Cb and Cr (chroma)
        default:
            bitsPerPixel = -1 // Unknown format
        }
        return bitsPerPixel
    }
    
    var bitmapInfo: CGBitmapInfo {
        let pixelFormat = CVPixelBufferGetPixelFormatType(self)
        var bitmapInfo: CGBitmapInfo = CGBitmapInfo()
        switch pixelFormat {
        case kCVPixelFormatType_8Indexed:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        case kCVPixelFormatType_16LE555:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
        case kCVPixelFormatType_32ARGB:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            // Add more cases for other pixel formats as needed
        default:
            bitmapInfo = CGBitmapInfo()
        }
        return bitmapInfo
    }
    
    var metalPixelFormat: MTLPixelFormat? {
        let pixelFormatType = CVPixelBufferGetPixelFormatType(self)
        switch pixelFormatType {
        case kCVPixelFormatType_32BGRA:
            return .bgra8Unorm
        case kCVPixelFormatType_32RGBA:
            return .rgba8Unorm
            // Add more cases for other pixel formats as needed
        default:
            return nil // Unknown pixel format
        }
    }
}

extension MTLTexture {
    var bitsPerPixel: Int {
        let pixelFormat = self.pixelFormat
        var bitsPerPixel = 0
        
        switch pixelFormat {
        case .r8Unorm, .r8Unorm_srgb, .r8Uint, .r8Sint:
            bitsPerPixel = 8
        case .rg8Unorm, .rg8Unorm_srgb, .rg8Uint, .rg8Sint:
            bitsPerPixel = 16
        case .rgba8Unorm, .rgba8Unorm_srgb, .rgba8Uint, .rgba8Sint:
            bitsPerPixel = 32
            // Add more cases for other pixel formats as needed
        default:
            bitsPerPixel = 0 // Unknown pixel format
        }
        
        return bitsPerPixel
    }
    
    var bitmapInfo: CGBitmapInfo {
        let pixelFormat = self.pixelFormat
        var bitmapInfo: CGBitmapInfo = CGBitmapInfo()
        
        switch pixelFormat {
        case .r8Unorm, .r8Unorm_srgb, .r8Uint, .r8Sint:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        case .rg8Unorm, .rg8Unorm_srgb, .rg8Uint, .rg8Sint:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
        case .rgba8Unorm, .rgba8Unorm_srgb, .rgba8Uint, .rgba8Sint:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            // Add more cases for other pixel formats as needed
        default:
            bitmapInfo = CGBitmapInfo()
        }
        
        return bitmapInfo
    }
}

#if os(iOS)
extension UIImage {
    var bitsPerPixel: Int {
        guard let cgImage = self.cgImage else {
            return -1
        }
        return cgImage.bitsPerPixel
    }
    
    var bitmapInfo: CGBitmapInfo {
        guard let cgImage = self.cgImage else {
            return CGBitmapInfo()
        }
        return cgImage.bitmapInfo
    }
}
#endif

#if os(macOS)
extension NSImage {
    var bitsPerPixel: Int? {
        guard let tiffData = self.tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return imageRep.bitsPerPixel
    }
    
    var nsBitmapInfo: NSBitmapImageRep? {
        guard let tiffData = self.tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return imageRep
    }
    
    var bitmapInfo: (bitsPerPixel: Int, bitmapInfo: CGBitmapInfo)? {
        // Get the TIFF representation of the NSImage
        guard let tiffData = self.tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        // Get bits per pixel
        let bitsPerPixel = imageRep.bitsPerPixel
        
        // Determine the CGBitmapInfo based on the alpha channel
        let alphaInfo: CGBitmapInfo
        
        switch imageRep.hasAlpha {
        case true:
            alphaInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        case false:
            alphaInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        }
        
        return (bitsPerPixel, alphaInfo)
    }
}
#endif
#endif

public enum ScaleMode: Sendable {
    case aspectFitVertical, aspectFitHorizontal, aspectFill, none
}
