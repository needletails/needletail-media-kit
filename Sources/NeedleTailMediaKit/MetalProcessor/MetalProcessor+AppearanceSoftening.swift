#if canImport(Metal) && canImport(Accelerate) && canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo

extension MetalProcessor {
    public enum VideoAppearanceSoftening {
        /// Subtle default: smooths skin without an obvious filter look (Zoom-style touch-up).
        public static let defaultBlendAmount = 0.45
    }

    /// Applies subtle appearance softening suitable for live camera frames.
    ///
    /// Zoom-style "touch up my appearance": a gentle smoothing that is weighted per pixel by a
    /// skin-tone mask derived from chroma. The mask is a pure function of each pixel's color, so
    /// it is temporally stable (no flutter) and needs no ML segmentation. Non-skin detail —
    /// hair, eyes, clothing, background edges — keeps its sharpness.
    ///
    /// Preserves the input pixel format so WebRTC capture can keep using NV12.
    public func applyAppearanceSoftening(
        to pixelBuffer: CVPixelBuffer,
        blendAmount: Double = VideoAppearanceSoftening.defaultBlendAmount
    ) async throws -> CVPixelBuffer {
        let input = CIImage(cvPixelBuffer: pixelBuffer)
        let softened = Self.softenCIImage(input, blendAmount: blendAmount)

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let pool = try pixelBufferPool(
            pixelFormat: format,
            width: width,
            height: height,
            metalCompatible: true
        )
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess,
              let output
        else {
            throw MetalScalingErrors.failedToCreateOutputPixelBuffer
        }
        textureRenderContext.render(softened, to: output)
        return output
    }

    static func softenCIImage(_ input: CIImage, blendAmount: Double) -> CIImage {
        let extent = input.extent
        let amount = max(0, min(1, blendAmount))
        guard amount > 0.001 else { return input }

        // Gentle smoothing layer. Blur sigma scales with frame size so the look is consistent
        // between 480p and 1080p captures.
        let sigma = max(1.5, min(extent.width, extent.height) / 240.0)
        let smoothed = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: extent)

        // Per-pixel skin-likelihood mask (chroma-based, temporally stable). Softened slightly so
        // the transition into non-skin areas is invisible.
        let skinMask = skinToneMask(for: input)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 2.0)
            .cropped(to: extent)

        // Scale mask strength by the user-facing amount.
        let weightedMask = skinMask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(amount), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(amount), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(amount), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])

        let blend = CIFilter.blendWithMask()
        blend.inputImage = smoothed
        blend.backgroundImage = input
        blend.maskImage = weightedMask
        return blend.outputImage?.cropped(to: extent) ?? input
    }

    /// Builds a skin-likelihood mask using a cached 32³ color cube.
    ///
    /// The cube maps RGB → white where the pixel's chroma falls inside the classic YCbCr skin
    /// ellipse (Cb 77–127, Cr 133–173, softened edges), black elsewhere. Being a per-pixel color
    /// lookup, the mask cannot flicker between frames the way ML segmentation can.
    private static func skinToneMask(for input: CIImage) -> CIImage {
        input.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": Self.skinCubeDimension,
            "inputCubeData": Self.skinToneCubeData,
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
    }

    private static let skinCubeDimension: NSNumber = 32

    /// Precomputed once; ~128KB.
    private static let skinToneCubeData: Data = {
        let size = 32
        var cube = [Float](repeating: 0, count: size * size * size * 4)
        var offset = 0
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rf = Float(r) / Float(size - 1)
                    let gf = Float(g) / Float(size - 1)
                    let bf = Float(b) / Float(size - 1)

                    // BT.601 RGB → CbCr (full range), the standard skin-detection space.
                    let R = rf * 255, G = gf * 255, B = bf * 255
                    let Cb = 128 - 0.168736 * R - 0.331264 * G + 0.5 * B
                    let Cr = 128 + 0.5 * R - 0.418688 * G - 0.081312 * B
                    let Y = 0.299 * R + 0.587 * G + 0.114 * B

                    // Soft membership in the skin chroma ellipse; very dark/bright pixels excluded.
                    let cbCenter: Float = 102, cbHalf: Float = 25
                    let crCenter: Float = 153, crHalf: Float = 20
                    let dcb = abs(Cb - cbCenter) / cbHalf
                    let dcr = abs(Cr - crCenter) / crHalf
                    let dist = dcb * dcb + dcr * dcr
                    var weight: Float = dist >= 1.6 ? 0 : (dist <= 0.7 ? 1 : (1.6 - dist) / 0.9)
                    if Y < 40 || Y > 250 { weight = 0 }

                    cube[offset] = weight
                    cube[offset + 1] = weight
                    cube[offset + 2] = weight
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }()

    static func blendCIImages(base: CIImage, overlay: CIImage, amount: Double) -> CIImage {
        let t = CGFloat(max(0, min(1, amount)))
        guard t > 0.001 else { return base }
        guard t < 0.999 else { return overlay }

        let baseScale = 1.0 - t
        let scaledBase = base.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: baseScale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: baseScale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: baseScale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
        let scaledOverlay = overlay.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: t, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: t, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: t, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
        let add = CIFilter.additionCompositing()
        add.inputImage = scaledOverlay
        add.backgroundImage = scaledBase
        return add.outputImage?.cropped(to: base.extent) ?? base
    }
}
#endif
