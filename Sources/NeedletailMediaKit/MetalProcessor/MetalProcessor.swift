//
//  MetalProcessor.swift
//  
//
//  Created by Cole M on 7/4/24.
//

@preconcurrency import Metal
@preconcurrency import MetalPerformanceShaders
@preconcurrency import MetalKit

public struct MetalProcessor: Sendable {
    
    enum MetalScalingErrors: Error, Sendable {
        case metalNotSupported, failedToCreateTextureCache, failedToCreateTextureCacheFromImage, failedToCreateTexture, failedToUnwrapTexture, failedToUnwrapTextureCache, failedToGetTexture, errorSettingUpEncoder, errorSettingUpCommandQueue, shaderFunctionNotFound, failedToCreateDataProvider, faileToCreateCGImage
    }
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let textureLoader: MTKTextureLoader
    
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
            fatalError("\(error)")
        }
    }
    
    private func createTexture(from pixelBuffer: CVPixelBuffer, device: MTLDevice) throws -> MTLTexture {
        var texture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        guard let textureCache = textureCache else { throw MetalScalingErrors.failedToUnwrapTextureCache }
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &texture) == kCVReturnSuccess else {
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
    
    private func convertYUVToRGB(cvPixelBuffer: CVPixelBuffer, device: MTLDevice) throws -> MTLTexture {
        // Create a Metal texture cache
        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        
        // Lock the base address of the CVPixelBuffer
        let baseAddress = CVPixelBufferLockBaseAddress(cvPixelBuffer, .readOnly)
        
        guard let textureCache = textureCache else {
            throw MetalScalingErrors.failedToCreateTextureCache
        }
        
        // Create Metal textures for Y and UV planes
        let yTexture = try createMTLTextureForPlane(cvPixelBuffer: cvPixelBuffer, planeIndex: 0, textureCache: textureCache, format: .r8Unorm, device: device)
        let uvTexture = try createMTLTextureForPlane(cvPixelBuffer: cvPixelBuffer, planeIndex: 1, textureCache: textureCache, format: .rg8Unorm, device: device)
        
        // Create a Metal texture for RGB output
        let rgbTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: CVPixelBufferGetWidth(cvPixelBuffer), height: CVPixelBufferGetHeight(cvPixelBuffer), mipmapped: false)
        rgbTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let rgbTexture = device.makeTexture(descriptor: rgbTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
        
        // Create a Metal compute pipeline with a shader that converts YUV to RGB
        let computePipeline = try createComputePipeline(device: device)
        
        // Set up a command buffer and encoder
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalScalingErrors.errorSettingUpEncoder
        }
        
        // Set textures and encode the compute shader
        computeEncoder.setComputePipelineState(computePipeline)
        computeEncoder.setTexture(yTexture, index: 0)
        computeEncoder.setTexture(uvTexture, index: 1)
        computeEncoder.setTexture(rgbTexture, index: 2)
        
        // Dispatch the compute shader
        let threadgroupCount = MTLSize(width: 8, height: 8, depth: 1)
        let threadgroupPerGrid = MTLSize(width: (rgbTexture.width + threadgroupCount.width - 1) / threadgroupCount.width,
                                         height: (rgbTexture.height + threadgroupCount.height - 1) / threadgroupCount.height,
                                         depth: 1)
        computeEncoder.dispatchThreadgroups(threadgroupPerGrid, threadsPerThreadgroup: threadgroupCount)
        computeEncoder.endEncoding()
        
        // Commit the command buffer
        commandBuffer.commit()
        
        // Unlock the CVPixelBuffer
        CVPixelBufferUnlockBaseAddress(cvPixelBuffer, .readOnly)
        
        return rgbTexture
    }

    func createMTLTextureForPlane(
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
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, cvPixelBuffer, nil, format, width, height, planeIndex, &cvTexture) == kCVReturnSuccess else {
            throw MetalScalingErrors.failedToCreateTextureCacheFromImage
        }
        
        guard let metalTexture = CVMetalTextureGetTexture(cvTexture!) else {
            throw MetalScalingErrors.failedToGetTexture
        }
        
        return metalTexture
    }

    func createComputePipeline(device: MTLDevice) throws -> MTLComputePipelineState {
        guard let shaderFunction = library.makeFunction(name: "ycbcrToRgb") else {
            throw MetalScalingErrors.shaderFunctionNotFound
        }
        return try device.makeComputePipelineState(function: shaderFunction)
    }

    
    public struct ScaledInfo: Sendable {
        public var size: CGSize
        public var scaleX: CGFloat
        public var scaleY: CGFloat
    }
    
    public func createSize(for scaleMode: ScaleMode = .none,
                            sourceSize: CGSize,
                            desiredSize: CGSize,
                            aspectRatio: CGFloat = 0
    ) async -> ScaledInfo {
        var size = CGSize()
        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        
        switch scaleMode {
        case .aspectFitVertical:
            size.width = desiredSize.height / aspectRatio
            size.height = desiredSize.height
            if sourceSize.width > sourceSize.height {
                size.height = desiredSize.height
                size.width = size.height * aspectRatio
            }
        case .aspectFitHorizontal:
            if aspectRatio != 0 {
                size.height = desiredSize.width / aspectRatio
            } else {
                size.height = desiredSize.height
            }
            size.width = desiredSize.width
            
            if sourceSize.width < sourceSize.height {
                size.width = desiredSize.width
                size.height = size.width * aspectRatio
            }
            
        case .aspectFill:
            if desiredSize.width > desiredSize.height {
                size.width = desiredSize.width
                if (desiredSize.width / aspectRatio) < desiredSize.height {
                    size.height = desiredSize.width * aspectRatio
                } else {
                    size.height = desiredSize.width / aspectRatio
                }
            } else {
                size.height = desiredSize.height
                if (desiredSize.height / aspectRatio) < desiredSize.width {
                    size.width = desiredSize.height * aspectRatio
                } else {
                    size.width = desiredSize.height / aspectRatio
                }
            }
        case .none:
            size.height = CGFloat(sourceSize.height)
            size.width = CGFloat(sourceSize.width)
        }
        
        scaleX = size.width / CGFloat(sourceSize.width)
        scaleY = size.height / CGFloat(sourceSize.height)
        
        return ScaledInfo(
            size: size,
            scaleX: scaleX,
            scaleY: scaleY)
    }

    
    func getAspectRatio(width: CGFloat, height: CGFloat) -> CGFloat {
        let width = width.rounded()
        let height = height.rounded()
        if width > height {
            return width / height
        } else {
            return height / width
        }
    }
    
    public func createMetalImage(
        fromPixelBuffer pixelBuffer: CVPixelBuffer,
        parentBounds: CGSize,
        newSize: CGSize,
        aspectRatio: CGFloat = 0,
        scaleMode: ScaleMode = .none
    ) async throws -> TextureInfo {
        var pixelBuffer = pixelBuffer
        let scaleInfo = await createSize(
            for: scaleMode,
            sourceSize: .init(width: pixelBuffer.width, height: pixelBuffer.height),
            desiredSize: newSize,
            aspectRatio: aspectRatio)
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var shouldConvertToRGB = false
        
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            shouldConvertToRGB = true
        default:
            shouldConvertToRGB = false
        }
        
        var texture: MTLTexture?
        if shouldConvertToRGB {
            texture = try convertYUVToRGB(cvPixelBuffer: pixelBuffer, device: self.device)
        } else {
            texture = try createTexture(from: pixelBuffer, device: device)
        }

        guard let texture = texture else { throw MetalScalingErrors.failedToUnwrapTexture }
        let resizedTexture = try resizeImage(
            sourceTexture: texture,
            parentBounds: parentBounds,
            newSize: scaleInfo.size,
            aspectRatio: aspectRatio,
            scaleX: scaleInfo.scaleX,
            scaleY: scaleInfo.scaleY)
        
        let mirrored = try mirrorTexture(sourceTexture: resizedTexture)

        let imageSize = CGSize(width: mirrored.width, height: mirrored.height)
        
        return try getTextureInfo(
            texture: mirrored,
            imageSize: imageSize,
            bitsPerPixel: pixelBuffer.bitsPerPixel,
            bitmapInfo: pixelBuffer.bitmapInfo)
    }
    
    private func resizeImage(
        sourceTexture: MTLTexture,
        parentBounds: CGSize,
        newSize: CGSize,
        aspectRatio: CGFloat,
        scaleX: Double,
        scaleY: Double
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
        let translateX = (Double(destTextureDescriptor.width) - Double(sourceTexture.width) * scaleX) / 2
        let translateY = (Double(destTextureDescriptor.height) - Double(sourceTexture.height) * scaleY) / 2
        let transform = MPSScaleTransform(
            scaleX: scaleX,
            scaleY: scaleY,
            translateX: translateX,
            translateY: translateY
        )
        
        let transformPointer = UnsafeMutablePointer<MPSScaleTransform>.allocate(capacity: 1)
        transformPointer.initialize(to: transform)
        filter.scaleTransform = UnsafePointer(transformPointer)
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        filter.encode(commandBuffer: commandBuffer!, sourceTexture: sourceTexture, destinationTexture: destTexture)
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        
        return destTexture
    }
    
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
    
    private func mirrorTexture(sourceTexture: MTLTexture) throws -> MTLTexture {
        let destinationTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                                width: sourceTexture.width,
                                                                                height: sourceTexture.height,
                                                                                mipmapped: false)
        destinationTextureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        guard let destinationTexture = device.makeTexture(descriptor: destinationTextureDescriptor) else {
            throw MetalScalingErrors.failedToCreateTexture
        }
            // Validate texture dimensions
            guard sourceTexture.width == destinationTexture.width && sourceTexture.height == destinationTexture.height else {
                fatalError("Source and destination textures must have the same dimensions")
            }
            
            // Create vertex data for a full-screen quad
            let vertices: [Float] = [
                -1.0, -1.0, 0.0, 0.0,  // bottom-left
                 1.0, -1.0, 0.0, 1.0,  // bottom-right
                -1.0,  1.0, 0.0, 0.0,  // top-left
                 1.0,  1.0, 0.0, 1.0   // top-right
            ]
            
            // Create vertex buffer
            let vertexBufferSize = vertices.count * MemoryLayout<Float>.stride
            guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertexBufferSize, options: []) else {
                fatalError("Failed to create vertex buffer")
            }
            
            // Create render pipeline state
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_shader")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_shader")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            
                let renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

            
            // Create command buffer and render pass descriptor
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                fatalError("Failed to create command buffer")
            }
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            
            renderPassDescriptor.colorAttachments[0].texture = destinationTexture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            // Create render command encoder
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                fatalError("Failed to create render command encoder")
            }
            
            // Set render pipeline state and vertex buffer
            renderEncoder.setRenderPipelineState(renderPipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            
            // Set fragment texture
            renderEncoder.setFragmentTexture(sourceTexture, index: 0)
            
            // Draw a full-screen quad
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            // End encoding and commit command buffer
            renderEncoder.endEncoding()
            commandBuffer.commit()
        return destinationTexture
        }
    
    private func createPixelBuffer(from texture: MTLTexture) -> CVPixelBuffer? {
        // 1. Create CVPixelBuffer attributes
        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        // 2. Create CVPixelBuffer
        var pixelBuffer: CVPixelBuffer?
        let width = texture.width
        let height = texture.height
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32BGRA,
                                         pixelBufferAttrs as CFDictionary,
                                         &pixelBuffer)
        
        guard status == kCVReturnSuccess, let unwrappedPixelBuffer = pixelBuffer else {
            print("Error: Failed to create CVPixelBuffer")
            return nil
        }
        
        // 3. Lock base address of the pixel buffer
        CVPixelBufferLockBaseAddress(unwrappedPixelBuffer, [])
        
        // 4. Create a Metal texture from the pixel buffer's base address
        let bytesPerPixel = 4 // BGRA format: 4 bytes per pixel
        let bytesPerRow = texture.width * bytesPerPixel
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        
        texture.getBytes(CVPixelBufferGetBaseAddress(unwrappedPixelBuffer)!,
                         bytesPerRow: bytesPerRow,
                         from: region,
                         mipmapLevel: 0)
        
        // 5. Unlock pixel buffer base address
        CVPixelBufferUnlockBaseAddress(unwrappedPixelBuffer, [])
        
        return unwrappedPixelBuffer
    }
    
#if os(iOS)
    private func createTexture(fromImage: UIImage, device: MTLDevice) -> MTLTexture? {
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
    
    
    public func resizeImage(from data: Data, newSize: CGSize) async throws -> UIImage {
        guard let uiImage = UIImage(data: data) else {
            fatalError()
            }
        return try await resizeImage(image: uiImage, newSize: newSize)
    }
    
    public func resizeImage(image: UIImage, newSize: CGSize) async throws -> UIImage {
        
        var scaleMode: ScaleMode = .aspectFill
        if image.size.width > image.size.height {
            scaleMode = .aspectFitHorizontal
        } else {
            scaleMode = .aspectFitVertical
        }
       
        guard let texture = createTexture(fromImage: image, device: device) else {
            fatalError()
        }
        let aspectRatio = getAspectRatio(width: image.size.width, height: image.size.height)
        let scaleInfo = await createSize(
            for: scaleMode,
            sourceSize: image.size,
            desiredSize: newSize,
            aspectRatio: aspectRatio)
        
        let resizedTexture = try resizeImage(
            sourceTexture: texture,
            parentBounds: newSize,
            newSize: scaleInfo.size,
            aspectRatio: aspectRatio,
            scaleX: scaleInfo.scaleX,
            scaleY: scaleInfo.scaleY)
        let imageSize = CGSize(width: resizedTexture.width, height: resizedTexture.height)
        let destinationTextureInfo = try getTextureInfo(
            texture: resizedTexture,
            imageSize: imageSize,
            bitsPerPixel: image.bitsPerPixel,
            bitmapInfo: image.bitmapInfo)

        guard let cgImage = CGImage(
            width: destinationTextureInfo.texture.width,
            height: destinationTextureInfo.texture.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: destinationTextureInfo.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: destinationTextureInfo.provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent) else { fatalError() }
        
        return UIImage(cgImage: cgImage)
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
    
    public func resizeImage(from data: Data, newSize: CGSize) async throws -> NSImage {
        guard let nsImage = NSImage(data: data) else {
            fatalError()
            }
        return try await resizeImage(image: nsImage, newSize: newSize)
    }
    
    public func resizeImage(image: NSImage, newSize: CGSize) async throws -> NSImage {

        var scaleMode: ScaleMode = .aspectFill
        if image.size.width > image.size.height {
            scaleMode = .aspectFitHorizontal
        } else {
            scaleMode = .aspectFitVertical
        }
        
        guard let texture = createTexture(fromImage: image, device: device) else {
            fatalError()
        }
        let aspectRatio = getAspectRatio(width: image.size.width, height: image.size.height)
        let scaleInfo = await createSize(
            for: scaleMode,
            sourceSize: image.size,
            desiredSize: newSize,
            aspectRatio: aspectRatio)
        

        
        let resizedTexture = try resizeImage(
            sourceTexture: texture,
            parentBounds: newSize,
            newSize: scaleInfo.size,
            aspectRatio: aspectRatio,
            scaleX: scaleInfo.scaleX,
            scaleY: scaleInfo.scaleY)
        let imageSize = CGSize(width: resizedTexture.width, height: resizedTexture.height)
        let destinationTextureInfo = try getTextureInfo(
            texture: resizedTexture,
            imageSize: imageSize,
            bitsPerPixel: image.bitsPerPixel,
            bitmapInfo: image.bitmapInfo)

        

        guard let cgImage = CGImage(
            width: destinationTextureInfo.texture.width,
            height: destinationTextureInfo.texture.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: destinationTextureInfo.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: destinationTextureInfo.bitmapInfo,
            provider: destinationTextureInfo.provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent) else { fatalError() }
        
        return NSImage(cgImage: cgImage, size: .init(width: cgImage.width, height: cgImage.height))
    }
#endif

}


import CoreMedia.CMTime
public struct TextureInfo: Sendable {
    var texture: MTLTexture
    var bytesPerRow: Int
    var bitmapInfo: CGBitmapInfo
    var provider: CGDataProvider
    var time: CMTime?
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
           switch CVPixelBufferGetPixelFormatType(self) {
           case kCVPixelFormatType_32BGRA:
               return CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
           case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
               return CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
           default:
               return CGBitmapInfo()
           }
       }
}

public enum ScaleMode: Sendable {
    case aspectFitVertical, aspectFitHorizontal, aspectFill, none
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
#elseif os(macOS)
extension NSImage {
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
