import XCTest
#if !SKIP && canImport(OSLog)
import OSLog
#endif
import Foundation
@testable import NeedleTailMediaKit

#if !SKIP && canImport(OSLog)
let logger: Logger = Logger(subsystem: "AndroidMediaKit", category: "Tests")
#else
// Dummy logger for SKIP/Android
struct Logger {
    func log(_ message: String) {}
}
let logger = Logger()
#endif

@available(macOS 13, *)
final class AndroidMediaKitTests: XCTestCase {

    func testAndroidMediaKit() throws {
        logger.log("running testAndroidMediaKit")
        XCTAssertEqual(1 + 2, 3, "basic test")
    }

    func testDecodeType() throws {
        // load the TestData.json file from the Resources folder and decode it into a struct
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
        XCTAssertEqual("AndroidMediaKit", testData.testModuleName)
    }

    // MARK: - ImageProcessor Tests (Android)
    // NOTE:
    // - The ImageProcessor Android implementation relies on Android Bitmap APIs via Skip transpilation.
    // - When running native Swift-on-Android tests (os(Android) without SKIP), image operations are expected
    //   to be unsupported.

    #if os(Android) && !SKIP
    func testImageProcessorUnsupportedOnNativeAndroid() async throws {
        let processor = ImageProcessor()
        let anyData = Data([0x89, 0x50, 0x4E, 0x47]) // looks like PNG header but is intentionally incomplete

        await assertThrowsUnsupportedImageFormat { try await processor.resizeImage(anyData, to: CGSize(width: 50, height: 50)) }
        await assertThrowsUnsupportedImageFormat { try await processor.applyBlur(to: anyData, radius: 5.0) }
        await assertThrowsUnsupportedImageFormat { try await processor.applySepia(to: anyData, intensity: 0.8) }
        await assertThrowsUnsupportedImageFormat { try await processor.convertToGrayscale(anyData) }
        await assertThrowsUnsupportedImageFormat { try await processor.adjustBrightnessContrast(image: anyData, brightness: 0.2, contrast: 1.3) }
    }

    private func assertThrowsUnsupportedImageFormat(_ operation: () async throws -> Data) async {
        do {
            _ = try await operation()
            XCTFail("Expected unsupportedImageFormat")
        } catch let error as ImageErrors {
            guard case .unsupportedImageFormat = error else {
                XCTFail("Expected unsupportedImageFormat, got: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    #else
    func testImageProcessorResize() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 100, height: 100)
        let resized = try await processor.resizeImage(pngData, to: CGSize(width: 50, height: 50))
        XCTAssertGreaterThan(resized.count, 0, "Resized image should have data")
        XCTAssertNotEqual(resized, pngData, "Resized image should be different from original")
    }

    func testImageProcessorBlur() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 50, height: 50)
        let blurred = try await processor.applyBlur(to: pngData, radius: 5.0)
        XCTAssertGreaterThan(blurred.count, 0, "Blurred image should have data")
        XCTAssertNotEqual(blurred, pngData, "Blurred image should be different from original")
    }

    func testImageProcessorSepia() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 50, height: 50)
        let sepia = try await processor.applySepia(to: pngData, intensity: 0.8)
        XCTAssertGreaterThan(sepia.count, 0, "Sepia image should have data")
        XCTAssertNotEqual(sepia, pngData, "Sepia image should be different from original")
    }

    func testImageProcessorGrayscale() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 50, height: 50)
        let grayscale = try await processor.convertToGrayscale(pngData)
        XCTAssertGreaterThan(grayscale.count, 0, "Grayscale image should have data")
        XCTAssertNotEqual(grayscale, pngData, "Grayscale image should be different from original")
    }

    func testImageProcessorBrightnessContrast() async throws {
        let processor = ImageProcessor()
        let pngData = createTestPNGData(width: 50, height: 50)
        let adjusted = try await processor.adjustBrightnessContrast(
            image: pngData,
            brightness: 0.2,
            contrast: 1.3
        )
        XCTAssertGreaterThan(adjusted.count, 0, "Adjusted image should have data")
        XCTAssertNotEqual(adjusted, pngData, "Adjusted image should be different from original")
    }

    func testImageProcessorInvalidInput() async throws {
        let processor = ImageProcessor()
        let invalidData = Data([0, 1, 2, 3])
        do {
            _ = try await processor.resizeImage(invalidData, to: CGSize(width: 10, height: 10))
            XCTFail("Should have thrown an error for invalid input")
        } catch let error as ImageErrors {
            switch error {
            case .invalidImageData, .unsupportedImageFormat:
                // Expected error
                break
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    #endif

    // MARK: - MediaCompressor Tests (Android)
    
    func testMediaCompressorScaledResolution() async {
        let compressor = MediaCompressor()
        let originalSize = CGSize(width: 1920, height: 1080)
        
        // Test downscaling - use explicit type for Skip
        let scaled640 = await compressor.scaledResolution(for: originalSize, using: MediaCompressor.AVAssetExportPreset.resolution640x480)
        XCTAssertEqual(scaled640.width, 640, accuracy: 1.0)
        XCTAssertEqual(scaled640.height, 480, accuracy: 1.0)
        
        // Test portrait orientation preservation
        let portraitOriginal = CGSize(width: 1080, height: 1920)
        let scaledPortrait = await compressor.scaledResolution(for: portraitOriginal, using: MediaCompressor.AVAssetExportPreset.resolution640x480)
        XCTAssertEqual(scaledPortrait.width, 480, accuracy: 1.0)
        XCTAssertEqual(scaledPortrait.height, 640, accuracy: 1.0)
        
        // Test when original is smaller than preset
        let smallOriginal = CGSize(width: 320, height: 240)
        let scaledSmall = await compressor.scaledResolution(for: smallOriginal, using: MediaCompressor.AVAssetExportPreset.resolution1920x1080)
        XCTAssertEqual(scaledSmall.width, 320, accuracy: 1.0)
        XCTAssertEqual(scaledSmall.height, 240, accuracy: 1.0)
    }

    func testMediaCompressorPresets() async {
        let compressor = MediaCompressor()
        let testSize = CGSize(width: 1920, height: 1080)
        
        // Test various presets - use explicit type for Skip
        let lowQuality = await compressor.scaledResolution(for: testSize, using: MediaCompressor.AVAssetExportPreset.lowQuality)
        XCTAssertLessThanOrEqual(lowQuality.width, testSize.width)
        XCTAssertLessThanOrEqual(lowQuality.height, testSize.height)
        
        let mediumQuality = await compressor.scaledResolution(for: testSize, using: MediaCompressor.AVAssetExportPreset.mediumQuality)
        XCTAssertLessThanOrEqual(mediumQuality.width, testSize.width)
        XCTAssertLessThanOrEqual(mediumQuality.height, testSize.height)
        
        let highestQuality = await compressor.scaledResolution(for: testSize, using: MediaCompressor.AVAssetExportPreset.highestQuality)
        XCTAssertLessThanOrEqual(highestQuality.width, testSize.width)
        XCTAssertLessThanOrEqual(highestQuality.height, testSize.height)
    }

    // MARK: - Helper Functions
    
    private func createTestPNGData(width: Int, height: Int) -> Data {
        #if SKIP
        // Android: Create a simple test image using Bitmap
        let bitmap = android.graphics.Bitmap.createBitmap(
            width,
            height,
            android.graphics.Bitmap.Config.ARGB_8888
        )
        
        // Fill with a gradient pattern
        for y in 0..<height {
            for x in 0..<width {
                let red = Float(x) / Float(width) * 255.0
                let green = Float(y) / Float(height) * 255.0
                let blue = 127.0
                let color = (0xFF << 24) | (Int(red) << 16) | (Int(green) << 8) | Int(blue)
                bitmap.setPixel(x, y, color)
            }
        }
        
        // Convert to PNG
        let outputStream = java.io.ByteArrayOutputStream()
        let success = bitmap.compress(
            android.graphics.Bitmap.CompressFormat.PNG,
            100,
            outputStream
        )
        
        if success {
            return Data(bytes: outputStream.toByteArray())
        }
        return Data()
        #elseif canImport(CoreGraphics) && canImport(ImageIO)
        // Apple: Use CoreGraphics (same as NeedleTailMediaKitTests.swift)
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
        #else
        // Fallback: return empty data
        return Data()
        #endif
    }

}

struct TestData : Codable, Hashable {
    var testModuleName: String
}
