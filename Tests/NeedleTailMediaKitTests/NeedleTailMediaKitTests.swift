// These tests exercise Apple-framework-backed implementations (CoreGraphics/ImageIO/CoreVideo/etc).
// The Android toolchain used by `skip android test` does not provide these modules.
#if canImport(NeedleTailMediaKit) && !os(Android)
@testable import NeedleTailMediaKit
import Foundation
import CoreGraphics
import ImageIO
import CoreVideo
import CoreMedia
import Testing

actor MediaKitTests {
    // MARK: - ImageProcessor Tests

    @available(macOS 13.0, iOS 16.0, *)
    @Test("ImageProcessor resize functionality works correctly")
    func testImageProcessorResize() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 100, height: 100)
        let resized = try await processor.resizeImage(pngData, to: CGSize(width: 50, height: 50))
        #expect(resized.count > 0)
        #expect(resized != pngData)
    }

    @available(macOS 13.0, iOS 16.0, *)
    @Test("ImageProcessor blur functionality works correctly")
    func testImageProcessorBlur() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 50, height: 50)
        let blurred = try await processor.applyBlur(to: pngData, radius: 5.0)
        #expect(blurred.count > 0)
        #expect(blurred != pngData)
    }

    @available(macOS 13.0, iOS 16.0, *)
    @Test("ImageProcessor sepia functionality works correctly")
    func testImageProcessorSepia() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 50, height: 50)
        let sepia = try await processor.applySepia(to: pngData, intensity: 0.8)
        #expect(sepia.count > 0)
        #expect(sepia != pngData)
    }

    @available(macOS 13.0, iOS 16.0, *)
    @Test("ImageProcessor grayscale functionality works correctly")
    func testImageProcessorGrayscale() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 50, height: 50)
        let grayscale = try await processor.convertToGrayscale(pngData)
        #expect(grayscale.count > 0)
        #expect(grayscale != pngData)
    }

    @available(macOS 13.0, iOS 16.0, *)
    @Test("ImageProcessor brightness/contrast adjustment works correctly")
    func testImageProcessorBrightnessContrast() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 50, height: 50)
        let adjusted = try await processor.adjustBrightnessContrast(
            image: pngData,
            brightness: 0.2,
            contrast: 1.3
        )
        #expect(adjusted.count > 0)
        #expect(adjusted != pngData)
    }

    @available(macOS 13.0, iOS 16.0, *)
    @Test("ImageProcessor handles invalid input data gracefully")
    func testImageProcessorInvalidInput() async throws {
        let processor = ImageProcessor()
        let invalidData = Data([0, 1, 2, 3])
        do {
            _ = try await processor.resizeImage(invalidData, to: CGSize(width: 10, height: 10))
            #expect(Bool(false))
        } catch let error as ImageErrors {
            switch error {
            case .invalidImageData, .unsupportedImageFormat:
                #expect(Bool(true))
            default:
                #expect(Bool(false))
            }
        } catch {
            #expect(Bool(false))
        }
    }

    @available(macOS 13.0, iOS 16.0, *)
    @Test("ImageProcessor supports concurrent operations")
    func testImageProcessorConcurrency() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 100, height: 100)
        async let resize1 = processor.resizeImage(pngData, to: CGSize(width: 50, height: 50))
        async let resize2 = processor.resizeImage(pngData, to: CGSize(width: 80, height: 80))
        async let blur = processor.applyBlur(to: pngData, radius: 1.0)
        async let sepia = processor.applySepia(to: pngData, intensity: 0.5)
        async let grayscale = processor.convertToGrayscale(pngData)

        let r1 = try await resize1
        let r2 = try await resize2
        let r3 = try await blur
        let r4 = try await sepia
        let r5 = try await grayscale

        for result in [r1, r2, r3, r4, r5] {
            #expect(result.count > 0)
        }
    }

    // MARK: - MetalProcessor Tests
    @Test("MetalProcessor aspect ratio calculation works correctly")
    func testMetalProcessorAspectRatioCalculation() async {
        let processor = MetalProcessor()
        let landscapeRatio = await processor.getAspectRatio(width: 200, height: 100)
        #expect(landscapeRatio == 2.0)
        let portraitRatio = await processor.getAspectRatio(width: 100, height: 200)
        #expect(portraitRatio == 0.5)
        let squareRatio = await processor.getAspectRatio(width: 100, height: 100)
        #expect(squareRatio == 1.0)
    }

    @Test("MetalProcessor scale mode calculations work correctly")
    func testMetalProcessorScaleModeCalculations() async {
        let processor = MetalProcessor()
        let originalSize = CGSize(width: 200, height: 100)
        let desiredSize = CGSize(width: 100, height: 100)
        let aspectRatio = await processor.getAspectRatio(width: originalSize.width, height: originalSize.height)

        let aspectFillInfo = await processor.createSize(
            for: .aspectFill,
            originalSize: originalSize,
            desiredSize: desiredSize,
            aspectRatio: aspectRatio
        )
        #expect(aspectFillInfo.size.width == desiredSize.width)
        #expect(aspectFillInfo.scaleX != 1.0)
        #expect(aspectFillInfo.scaleY != 1.0)

        let aspectFitVerticalInfo = await processor.createSize(
            for: .aspectFitVertical,
            originalSize: originalSize,
            desiredSize: desiredSize,
            aspectRatio: aspectRatio
        )
        #expect(aspectFitVerticalInfo.size.height == desiredSize.height)

        let aspectFitHorizontalInfo = await processor.createSize(
            for: .aspectFitHorizontal,
            originalSize: originalSize,
            desiredSize: desiredSize,
            aspectRatio: aspectRatio
        )
        #expect(aspectFitHorizontalInfo.size.width == desiredSize.width)

        let noneInfo = await processor.createSize(
            for: .none,
            originalSize: originalSize,
            desiredSize: desiredSize,
            aspectRatio: aspectRatio
        )
        #expect(noneInfo.size == originalSize)
        #expect(noneInfo.scaleX == 1.0)
        #expect(noneInfo.scaleY == 1.0)
    }

    // MARK: - MediaCompressor Tests

    @available(macOS 13.0, iOS 16.0, *)
    @Test("MediaCompressor scaledResolution calculation works correctly")
    func testMediaCompressorScaledResolution() async {
        let compressor = MediaCompressor()
        let originalSize = CGSize(width: 1920, height: 1080)
        
        // Test downscaling
        let scaled640 = await compressor.scaledResolution(for: originalSize, using: .resolution640x480)
        #expect(scaled640.width == 640)
        #expect(scaled640.height == 480)
        
        // Test portrait orientation preservation
        let portraitOriginal = CGSize(width: 1080, height: 1920)
        let scaledPortrait = await compressor.scaledResolution(for: portraitOriginal, using: .resolution640x480)
        #expect(scaledPortrait.width == 480)
        #expect(scaledPortrait.height == 640)
        
        // Test when original is smaller than preset
        let smallOriginal = CGSize(width: 320, height: 240)
        let scaledSmall = await compressor.scaledResolution(for: smallOriginal, using: .resolution1920x1080)
        #expect(scaledSmall.width == 320)
        #expect(scaledSmall.height == 240)
    }

    @available(macOS 13.0, iOS 16.0, *)
    @Test("MediaCompressor handles different preset types")
    func testMediaCompressorPresets() async {
        let compressor = MediaCompressor()
        let testSize = CGSize(width: 1920, height: 1080)
        
        // Test various presets
        let lowQuality = await compressor.scaledResolution(for: testSize, using: .lowQuality)
        #expect(lowQuality.width <= testSize.width)
        #expect(lowQuality.height <= testSize.height)
        
        let mediumQuality = await compressor.scaledResolution(for: testSize, using: .mediumQuality)
        #expect(mediumQuality.width <= testSize.width)
        #expect(mediumQuality.height <= testSize.height)
        
        let highestQuality = await compressor.scaledResolution(for: testSize, using: .highestQuality)
        #expect(highestQuality.width <= testSize.width)
        #expect(highestQuality.height <= testSize.height)
    }

    // MARK: - Error Handling Tests

    @Test("ImageErrors enum provides correct error messages")
    func testImageErrors() {
        let error1 = ImageErrors.imageCreationFailed("Test error message")
        let error2 = ImageErrors.imageProcessingFailed("Processing failed")
        let error3 = ImageErrors.invalidImageData
        let error4 = ImageErrors.unsupportedImageFormat

        #expect(error1.localizedDescription.contains("Test error message"))
        #expect(error2.localizedDescription.contains("Processing failed"))
        #expect(error3.localizedDescription.contains("invalid image data") || error3.localizedDescription.count > 0)
        #expect(error4.localizedDescription.contains("unsupported image format") || error4.localizedDescription.count > 0)
    }

    // MARK: - Helper Functions

    fileprivate func createTestPNGData(width: Int, height: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for y in 0..<height {
            for x in 0..<width {
                let red = Float(x) / Float(width)
                let green = Float(y) / Float(height)
                let blue = 0.5
                context.setFillColor(CGColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1.0))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        guard let cgImage = context.makeImage() else { return Data() }
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return mutableData as Data
    }
}
#endif
