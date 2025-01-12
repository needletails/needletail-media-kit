#if os(iOS) || os(macOS)
//
//  Untitled.swift
//
//
//  Created by Cole M on 6/24/24.
//
@preconcurrency import Metal
@preconcurrency import MetalPerformanceShaders
import MetalKit
import Vision
import CoreMedia.CMTime

public actor MetalProcessor {
    
    enum MetalScalingErrors: Error, Sendable {
        case metalNotSupported, failedToCreateTextureCache, failedToCreateTextureCacheFromImage, failedToCreateTexture, failedToUnwrapTexture, failedToUnwrapTextureCache, failedToGetTexture, errorSettingUpEncoder, errorSettingUpCommandQueue, shaderFunctionNotFound, failedToCreateDataProvider, failedToCreateOutputPixelBuffer, failedToCreatePixelBufferPool, failedToLockPixelBuffer, failedToCreatePipeline, sampleBufferCreationError
    }
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let textureLoader: MTKTextureLoader
    var flipKernelPipeline: MTLComputePipelineState?
    var ycbcrToRgbKernelPipeline: MTLComputePipelineState?
    var rgbToYuvKernelPipeline: MTLComputePipelineState?
    var i420ToRgbKernelPipeline: MTLComputePipelineState?
    var blurPipelineState: MTLComputePipelineState?
    let colorSpace: [CIImageOption: Any] = [CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB()]

    
    public init() {
        do {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw MetalScalingErrors.metalNotSupported
            }
            self.device = device
            library = try device.makeDefaultLibrary(bundle: Bundle.module)
            guard let commandQueue = device.makeCommandQueue() else {
                throw MetalScalingErrors.errorSettingUpCommandQueue
            }
            self.commandQueue = commandQueue
            self.textureLoader = MTKTextureLoader(device: device)
        } catch {
            fatalError("Metal Not Supported: \(error)")
        }
    }
    
    public func createTexture(from pixelBuffer: CVPixelBuffer, device: MTLDevice) throws -> MTLTexture {
        var texture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        defer {
            if let textureCache = textureCache {
                CVMetalTextureCacheFlush(textureCache, 0)
            }
        }
        guard let textureCache = textureCache else { throw MetalScalingErrors.failedToUnwrapTextureCache }
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
    
    public func convertYUVToRGB(
        cvPixelBuffer: CVPixelBuffer,
        device: MTLDevice
    ) throws -> MTLTexture {
        // Create a Metal texture cache if not already created
        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess,
              let cache = textureCache else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        
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
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
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
        
        // Calculate threadgroup and grid sizes
        let threadgroupCount = MTLSize(width: 8, height: 8, depth: 1)
        let threadsPerThreadgroup = MTLSize(
            width: (rgbTexture.width + threadgroupCount.width - 1) / threadgroupCount.width,
            height: (rgbTexture.height + threadgroupCount.height - 1) / threadgroupCount.height,
            depth: 1)
        defer {
            computeEncoder.endEncoding()
            commandBuffer.commit()
        }
        computeEncoder.dispatchThreadgroups(threadsPerThreadgroup, threadsPerThreadgroup: threadgroupCount)
        
        
        // Return the RGB texture
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
        
        if let cache = cvTexture, let metalTexture = CVMetalTextureGetTexture(cache) {
            return metalTexture
        } else {
            throw MetalScalingErrors.failedToGetTexture
        }
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
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
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
        
        // Calculate threadgroup and grid sizes
        let threadgroupCount = MTLSize(width: 8, height: 8, depth: 1)
        let threadsPerThreadgroup = MTLSize(
            width: (rgbTexture.width + threadgroupCount.width - 1) / threadgroupCount.width,
            height: (rgbTexture.height + threadgroupCount.height - 1) / threadgroupCount.height,
            depth: 1)
        
        computeEncoder.dispatchThreadgroups(threadsPerThreadgroup, threadsPerThreadgroup: threadgroupCount)
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
            size.width = aspectRatio != 0 ? desiredSize.height / aspectRatio : desiredSize.width
            size.height = desiredSize.height
            
            if originalSize.width > originalSize.height {
                size.height = desiredSize.height
                size.width = size.height * aspectRatio
            }
            
        case .aspectFitHorizontal:
            //This is correct for horizontal, don't change it
            size.height = aspectRatio != 0 ? desiredSize.width / aspectRatio : desiredSize.height
            size.width = desiredSize.width
            
            if originalSize.width < originalSize.height {
                size.width = desiredSize.width
                size.height = size.width * aspectRatio
            }
            
        case .aspectFill:
            //This is correct for fill, don't change it
            if originalSize.width > originalSize.height {
                size.width = desiredSize.width
                size.height = aspectRatio != 0 ? desiredSize.width / aspectRatio : desiredSize.height
            } else {
                size.height = desiredSize.height
                size.width = aspectRatio != 0 ? desiredSize.height / aspectRatio : desiredSize.width
            }
            
        case .none:
            size.width = originalSize.width
            size.height = originalSize.height
        }
        
        scaleX = size.width / originalSize.width
        scaleY = size.height / originalSize.height
        return ScaledInfo(size: size, scaleX: scaleX, scaleY: scaleY)
    }
    
    
    public func getAspectRatio(width: CGFloat, height: CGFloat) -> CGFloat {
        let width = width
        let height = height
        if width > height {
            return width / height
        } else {
            return height / width
        }
    }
    
#if canImport(WebRTC)
    public func createMetalImage(
        fromPixelBuffer pixelBuffer: CVPixelBuffer? = nil,
        fromI420Buffer i420: RTCI420Buffer? = nil,
        parentBounds: CGSize,
        scaleInfo: ScaledInfo,
        aspectRatio: CGFloat
    ) async throws -> TextureInfo {
        if let pixelBuffer = pixelBuffer {
            let texture = try convertYUVToRGB(
                cvPixelBuffer: pixelBuffer,
                device: self.device)
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
        
        //DESTINATION NEEDS TO BE SIZE OF PARENT VIEW
        let destTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sourceTexture.pixelFormat,
                                                                             width: Int(parentBounds.width),
                                                                             height: Int(parentBounds.height),
                                                                             mipmapped: false)
        destTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let destTexture = device.makeTexture(descriptor: destTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        
        let translateX = (Double(destTextureDescriptor.width) - Double(sourceTexture.width) * scaleInfo.scaleX) / 2
        let translateY = (Double(destTextureDescriptor.height) - Double(sourceTexture.height) * scaleInfo.scaleY) / 2
        
        let transform = MPSScaleTransform(
            scaleX: scaleInfo.scaleX,
            scaleY: scaleInfo.scaleY,
            translateX: translateX,
            translateY: translateY
        )
        
        let transformPointer = UnsafeMutablePointer<MPSScaleTransform>.allocate(capacity: 1)
        transformPointer.initialize(to: transform)
        filter.scaleTransform = UnsafePointer(transformPointer)
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { throw MetalScalingErrors.errorSettingUpCommandQueue }
        defer {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            transformPointer.deallocate()
        }
        filter.encode(commandBuffer: commandBuffer,
                      sourceTexture: sourceTexture,
                      destinationTexture: destTexture)
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
    
    public func mirrorTexture(sourceTexture: MTLTexture) throws -> MTLTexture {
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
        guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalScalingErrors.errorSettingUpEncoder
        }
        
        guard let flipKernelPipeline = flipKernelPipeline else {
            throw MetalScalingErrors.failedToCreatePipeline
        }
        // Set Compute Pipeline State
        computeEncoder.setComputePipelineState(flipKernelPipeline)
        
        var horizontal: Bool = true // Assuming you have a boolean indicating horizontal flip
        var vertical: Bool = false
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
        }
        
        // Return Destination Texture
        return destinationTexture
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
        defer {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        filter.encode(commandBuffer: commandBuffer,
                      sourceTexture: sourceTexture,
                      destinationTexture: destTexture)
        return destTexture
    }
    
#if os(iOS)
    public func createImage(from texture: MTLTexture, colorSpace: [CIImageOption: Any] = [CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB()]) async -> UIImage {
        guard let ciImage = CIImage(mtlTexture: texture, options: colorSpace) else { fatalError() }
        let orientedImage = ciImage.oriented(forExifOrientation: 4)
        return UIImage(ciImage: orientedImage)
    }
#elseif os(macOS)
    public func createImage(from texture: MTLTexture, colorSpace: [CIImageOption: Any] = [CIImageOption.colorSpace: CGColorSpaceCreateDeviceRGB()]) async -> NSImage {
        guard let ciImage = CIImage(mtlTexture: texture, options: colorSpace) else { fatalError() }
        let orientedImage = ciImage.oriented(forExifOrientation: 4)
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(orientedImage, from: orientedImage.extent) else {
            fatalError()
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
        // Pixel buffer attributes
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: y.width,
            kCVPixelBufferHeightKey as String: y.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true // Ensure Metal compatibility
        ]
        
        // Create a pixel buffer pool
        var pixelBufferPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, pixelBufferAttributes as CFDictionary, &pixelBufferPool)
        guard status == kCVReturnSuccess, let pool = pixelBufferPool else {
            throw MetalScalingErrors.failedToCreatePixelBufferPool
        }
        
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
        CVPixelFormatDescriptionCreateWithPixelFormatType(kCFAllocatorDefault, .zero)
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
        // Pixel buffer attributes
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: parentBounds.width,
            kCVPixelBufferHeightKey as String: parentBounds.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        // Create a pixel buffer pool
        var pixelBufferPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, pixelBufferAttributes as CFDictionary, &pixelBufferPool)
        guard status == kCVReturnSuccess, let pool = pixelBufferPool else {
            throw MetalScalingErrors.failedToCreatePixelBufferPool
        }
        
        // Create a texture cache
        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess, let cache = textureCache else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        defer {
            if let textureCache = textureCache {
                CVMetalTextureCacheFlush(textureCache, 0)
            }
        }
        // Lock the base address of the input CVPixelBuffer
       _ = CVPixelBufferLockBaseAddress(cvPixelBuffer, .readOnly)
        
        // Create textures for Y and UV planes
        let yTexture = try createMTLTextureForPlane(cvPixelBuffer: cvPixelBuffer, planeIndex: 0, textureCache: cache, format: .r8Unorm, device: device)
        let uvTexture = try createMTLTextureForPlane(cvPixelBuffer: cvPixelBuffer, planeIndex: 1, textureCache: cache, format: .rg8Unorm, device: device)
        
        // Resize textures
        //        let resizedY = try resizeImage(sourceTexture: yTexture, parentBounds: parentBounds, scaleInfo: scaleInfo, aspectRatio: aspectRatio)
        //        let resizedUV = try resizeImage(sourceTexture: uvTexture, parentBounds: CGSize(width: parentBounds.width / 2, height: parentBounds.height / 2), scaleInfo: scaleInfo, aspectRatio: aspectRatio)
        
        // Create output pixel buffer
        var outputPixelBuffer: CVPixelBuffer?
//        let width = yTexture.width
//        let height = yTexture.height
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
        let attributes: [NSString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: ciImage.extent.width,
            kCVPixelBufferHeightKey: ciImage.extent.height,
            kCVPixelBufferIOSurfacePropertiesKey: [:], // Empty dictionary for default properties
            kCVPixelBufferMetalCompatibilityKey: true // Ensure Metal compatibility
        ]
        
        
        var pixelBufferPool: CVPixelBufferPool?
        
        _ = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pixelBufferPool)
        
        var pixelBuffer: CVPixelBuffer?
        let poolStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool!, &pixelBuffer)
        
        guard let unwrappedPixelBuffer = pixelBuffer, poolStatus == kCVReturnSuccess else {
            print("Failed to create pixel buffer from pool. Status: \(poolStatus)")
            return nil
        }
        let orientedImage = ciImage.oriented(forExifOrientation: 4)
        ciContext.render(orientedImage, to: unwrappedPixelBuffer)
        return unwrappedPixelBuffer
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
    
    public func createi420Texture(from i420Buffer: RTCI420Buffer, device: MTLDevice) throws -> MTLTexture {
        let yPlane = i420Buffer.dataY
        let uPlane = i420Buffer.dataU
        let vPlane = i420Buffer.dataV
        
        let textures = try createMetalTexturesFromYUVPlanes(
            yData: yPlane,
            uData: uPlane,
            vData: vPlane,
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
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
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
        
        // Dispatch the compute shader
        let threadgroupCount = MTLSize(width: 8, height: 8, depth: 1)
        let threadgroupPerGrid = MTLSize(width: (rgbTexture.width + threadgroupCount.width - 1) / threadgroupCount.width,
                                         height: (rgbTexture.height + threadgroupCount.height - 1) / threadgroupCount.height,
                                         depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupPerGrid, threadsPerThreadgroup: threadgroupCount)
        defer {
            computeEncoder.endEncoding()
            commandBuffer.commit()
        }
        return rgbTexture
    }
    
    public func createMetalTexturesFromYUVPlanes(
        yData: UnsafePointer<UInt8>,
        uData: UnsafePointer<UInt8>,
        vData: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        device: MTLDevice
    ) throws -> I420Textures {
        
        let bytesPerPixelY = 1
        let bytesPerPixelUV = 1 // U and V are subsampled by a factor of 2 horizontally and vertically
        let bytesPerRowY = bytesPerPixelY * width
        let bytesPerRowUV = bytesPerPixelUV * (width / 2)
        
        // Create Metal texture for Y component (luminance)
        let textureDescriptorY = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptorY.usage = [.shaderRead, .shaderWrite]
        
        guard let yTexture = device.makeTexture(descriptor: textureDescriptorY) else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        
        let regionY = MTLRegionMake2D(0, 0, width, height)
        yTexture.replace(region: regionY, mipmapLevel: 0, withBytes: yData, bytesPerRow: bytesPerRowY)
        
        // Create Metal texture for U component (chrominance)
        let textureDescriptorU = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width / 2, height: height / 2, mipmapped: false)
        textureDescriptorU.usage = [.shaderRead, .shaderWrite]
        
        guard let uTexture = device.makeTexture(descriptor: textureDescriptorU) else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        
        let regionU = MTLRegionMake2D(0, 0, width / 2, height / 2)
        uTexture.replace(region: regionU, mipmapLevel: 0, withBytes: uData, bytesPerRow: bytesPerRowUV)
        
        // Create Metal texture for V component (chrominance)
        let textureDescriptorV = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width / 2, height: height / 2, mipmapped: false)
        textureDescriptorV.usage = [.shaderRead, .shaderWrite]
        
        guard let vTexture = device.makeTexture(descriptor: textureDescriptorV) else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        
        let regionV = MTLRegionMake2D(0, 0, width / 2, height / 2)
        vTexture.replace(region: regionV, mipmapLevel: 0, withBytes: vData, bytesPerRow: bytesPerRowUV)
        
        return I420Textures(
            yTexture: yTexture,
            uTexture: uTexture,
            vTexture: vTexture)
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
                fatalError()
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
            parentBounds: info.size
            ,
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
                fatalError()
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
        let aspectRatio = await getAspectRatio(width: originalSize.width, height: originalSize.height)
        let info = await createSize(for: .aspectFill, originalSize: originalSize, desiredSize: desiredSize, aspectRatio: aspectRatio)
        
        let textureInfo = try await resizeImage(
            image: image,
            parentBounds: desiredSize,
            scaleInfo: info,
            aspectRatio: aspectRatio
        )
        return textureInfo.texture
    }
#endif
}

//extension MetalProcessor {
//
//    @available(iOS 15, *)
//    @SegmentationActor struct SegementationRequest {
//        static let request = VNGeneratePersonSegmentationRequest()
//    }
//
//    @available(iOS 15, *)
//    /// This method is used when an image has been selected for Virtual Background. We are using Vision.framework to get the person segmentation mask
//    /// - Parameters:
//    ///   - pixelBuffer: Our `AVCaptureOutput` `CVPixelBuffer`
//    ///   - backgroundBuffer: The `CVPixelBuffer` created from the Virtual Background Image
//    ///   - ciContext: The render's `CIContext`
//    /// - Returns: `ImageObject?`
//    internal func processVideoFrame(_
//                                    vbPacket: VirtualBackgroundPacket,
//                                    originalAspectRatio: CGFloat,
//                                    bounds: CGSize,
//                                    ciContext: CIContext,
//                                    scaleMode: ScaleMo,
//                                    metalScaler: MetalScaler,
//                                    backgroundType: VirtualBackgroundType
//    ) async throws -> TextureInfo {
//
//        guard let foregroundPixels = vbPacket.foregroundPixels else { throw ACBClientErrors.pixelBufferCreationError }
//
//        let aspectRatio = await metalScaler.getAspectRatio(
//            width: CGFloat(foregroundPixels.width),
//            height: CGFloat(foregroundPixels.height))
//
//        let scaleInfo = await metalScaler.createSize(
//            for: scaleMode,
//            originalSize: CGSize(
//                width: foregroundPixels.width,
//                height: foregroundPixels.height),
//            desiredSize: CGSize(
//                width: bounds.width,
//                height: bounds.height
//            ),
//            aspectRatio: aspectRatio)
//
//        var foregroundInfo = try await metalScaler.createMetalImage(
//            fromPixelBuffer: foregroundPixels,
//            parentBounds: bounds,
//            scaleInfo: scaleInfo,
//            aspectRatio: aspectRatio
//        )
//
//        guard let foregroundImage = CGImage(
//            width: foregroundInfo.texture.width,
//            height: foregroundInfo.texture.height,
//            bitsPerComponent: 8,
//            bitsPerPixel: 32,
//            bytesPerRow: foregroundInfo.bytesPerRow,
//            space: CGColorSpaceCreateDeviceRGB(),
//            bitmapInfo: foregroundInfo.bitmapInfo,
//            provider: foregroundInfo.provider,
//            decode: nil,
//            shouldInterpolate: true,
//            intent: .defaultIntent) else { throw ACBClientErrors.imageCreationFailed }
//
//        let foregroundBounds = CGSize(width: foregroundInfo.texture.width, height: foregroundInfo.texture.height)
//        // Create request handler
//        let request = await SegementationRequest.request
//        request.qualityLevel = .balanced
//        let handler = VNImageRequestHandler(
//            cgImage: foregroundImage,
//            orientation: .up,
//            options: [.ciContext: ciContext])
//
//        try handler.perform([request])
//
//        guard let mask = request.results?.first else {
//            throw ACBClientErrors.cannotProcessBackgroundImage
//        }
//
//        let ciImage = CIImage(cvPixelBuffer: mask.pixelBuffer)
//        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { throw ACBClientErrors.imageCreationFailed }
//        let maskImage = UIImage(cgImage: cgImage)
//
//
//        let maskAspectRatio = await metalScaler.getAspectRatio(width: CGFloat(foregroundImage.width), height: CGFloat(foregroundImage.height))
//        let maskScaleInfo = await metalScaler.createSize(
//            for: scaleMode,
//            originalSize: CGSize(
//                width: maskImage.size.width,
//                height: maskImage.size.height),
//            desiredSize: CGSize(
//                width: foregroundImage.width,
//                height: foregroundImage.height
//            ),
//            aspectRatio: maskAspectRatio)
//
//        var maskInfo = try await metalScaler.resizeImage(
//            image: maskImage,
//            parentBounds: foregroundBounds,
//            scaleInfo: maskScaleInfo,
//            aspectRatio: maskAspectRatio
//        )
//
//        var backgroundCGImage: CGImage?
//        if let backgroundImage = vbPacket.backgroundImage {
//            let backgroundAspectRatio = await metalScaler.getAspectRatio(width: CGFloat(backgroundImage.size.width), height: CGFloat(backgroundImage.size.height))
//            let backgroundScaleInfo = await metalScaler.createSize(
//                for: UIDevice.current.orientation.isLandscape ? .horizontal : .vertical,
//                originalSize: CGSize(
//                    width: backgroundImage.size.width,
//                    height: backgroundImage.size.height),
//                desiredSize: CGSize(
//                    width: foregroundImage.width,
//                    height: foregroundImage.height
//                ),
//                aspectRatio: maskAspectRatio)
//            var backgroundInfo = try await metalScaler.resizeImage(
//                image: backgroundImage,
//                parentBounds: foregroundBounds,
//                scaleInfo: backgroundScaleInfo,
//                aspectRatio: backgroundAspectRatio
//            )
//
//            backgroundCGImage = CGImage(
//                width: backgroundInfo.texture.width,
//                height: backgroundInfo.texture.height,
//                bitsPerComponent: 8,
//                bitsPerPixel: 32,
//                bytesPerRow: backgroundInfo.bytesPerRow,
//                space: CGColorSpaceCreateDeviceRGB(),
//                bitmapInfo: backgroundInfo.bitmapInfo,
//                provider: backgroundInfo.provider,
//                decode: nil,
//                shouldInterpolate: true,
//                intent: .defaultIntent)
//        }
//
//        guard let foregroundImage = CGImage(
//            width: foregroundInfo.texture.width,
//            height: foregroundInfo.texture.height,
//            bitsPerComponent: 8,
//            bitsPerPixel: 32,
//            bytesPerRow: foregroundInfo.bytesPerRow,
//            space: CGColorSpaceCreateDeviceRGB(),
//            bitmapInfo: foregroundInfo.bitmapInfo,
//            provider: foregroundInfo.provider,
//            decode: nil,
//            shouldInterpolate: true,
//            intent: .defaultIntent) else { throw ACBClientErrors.imageCreationFailed }
//
//        guard let maskImage = CGImage(
//            width: maskInfo.texture.width,
//            height: maskInfo.texture.height,
//            bitsPerComponent: 8,
//            bitsPerPixel: 32,
//            bytesPerRow: maskInfo.bytesPerRow,
//            space: CGColorSpaceCreateDeviceRGB(),
//            bitmapInfo: maskInfo.bitmapInfo,
//            provider: maskInfo.provider,
//            decode: nil,
//            shouldInterpolate: true,
//            intent: .defaultIntent) else { fatalError() }
//
//
//
//        return try await blendImages(
//            backgroundType: backgroundType,
//            foregroundImage: CIImage(cgImage: foregroundImage),
//            maskImage: CIImage(cgImage: maskImage),
//            backgroundImage: (backgroundCGImage != nil) ? CIImage(cgImage: backgroundCGImage!) : CIImage(cgImage: foregroundImage),
//            ciContext: ciContext,
//            scaleMode: scaleMode,
//            metalScaler: metalScaler
//        )
//    }
//
//    /// This method is designed to take 3 buffer in order to blend them together and delivers a single object containg the Virtual Background Image
//    /// - Parameters:
//    ///   - foregroundBuffer: The `CVPixelBuffer` containing the original `AVCaptureOutput` image
//    ///   - maskedBuffer: The `CVPixelBuffer` containing the Vision.framework masked  image
//    ///   - backgroundBuffer: The `CVPixelBuffer` containing the background  image
//    ///   - ciContext: The renderer's `CIContext`
//    /// - Returns: `ImageObject?`
//    @available(iOS 14, *)
//    private func blendImages(
//        backgroundType: VirtualBackgroundType,
//        foregroundImage: CIImage,
//        maskImage: CIImage,
//        backgroundImage: CIImage,
//        ciContext: CIContext,
//        scaleMode: VideoScaleMode,
//        metalScaler: MetalScaler
//    ) async throws -> TextureInfo {
//        let blendFilter = CIFilter.blendWithMask()
//
//        switch backgroundType {
//        case .cameraBlur:
//            let blurredImage = backgroundImage
//                .clampedToExtent()
//                .applyingGaussianBlur(sigma: 10.0)
//                .cropped(to: backgroundImage.extent)
//            blendFilter.inputImage = foregroundImage
//            blendFilter.backgroundImage = blurredImage
//            blendFilter.maskImage = maskImage
//
//        case .imageBlur:
//            break
//        case .image:
//            blendFilter.inputImage = foregroundImage
//            blendFilter.backgroundImage = backgroundImage
//            blendFilter.maskImage = maskImage
//        }
//        guard let image = blendFilter.outputImage else { throw ACBClientErrors.imageCreationFailed }
//
//        let aspectRatio = await getAspectRatio(
//            width: CGFloat(image.extent.width),
//            height: CGFloat(image.extent.height))
//
//        let scaleInfo = await createSize(
//            for: scaleMode,
//            originalSize: CGSize(
//                width: image.extent.width,
//                height: image.extent.height),
//            desiredSize: CGSize(
//                width: image.extent.size.width,
//                height: image.extent.size.height
//            ),
//            aspectRatio: aspectRatio)
//
//        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { throw ACBClientErrors.imageCreationFailed }
//        let uiImage = UIImage(cgImage: cgImage)
//        return try await resizeImage(
//            image: uiImage,
//            parentBounds: uiImage.size,
//            scaleInfo: scaleInfo,
//            aspectRatio: aspectRatio)
//    }
//}


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

public enum ScaleMode: Sendable {
    case aspectFitVertical, aspectFitHorizontal, aspectFill, none
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
