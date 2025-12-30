//
//  MediaCompression.swift
//  needletail-media-kit
//
//  Created by Cole M on 8/25/24.
//
import Foundation
#if os(iOS) || os(macOS) && canImport(AVFoundation) && canImport(CoreImage)
import AVFoundation
import CoreImage
import UniformTypeIdentifiers
#endif

/// Cross-platform file type representation
/// On Apple: Uses AVFileType from AVFoundation
/// On Android: Uses String since AVFileType is not available
#if os(Android)
public typealias MediaFileType = String
#elseif canImport(AVFoundation)
public typealias MediaFileType = AVFileType
#else
// Fallback for platforms without AVFoundation
public typealias MediaFileType = String
#endif

public actor MediaCompressor {
    
    #if os(Android)
    private let androidCompressor: AndroidMediaCompressor
    #endif
    
    public init() {
        #if os(Android)
        self.androidCompressor = AndroidMediaCompressor()
        #endif
    }
    
    public enum CompressionErrors: Error, Sendable {
        case failedToCreateExportSession, noVideoTrack
        case unsupportedPlatform
    }
    
    /// Helper to extract file type string from AVFileType in a cross-platform way
    /// On Apple platforms, extracts the rawValue from AVFileType
    /// On Android, infers from URL extension or uses defaults since AVFileType is not available
    #if os(Android)
    private nonisolated func fileTypeString(from fileType: MediaFileType, defaultExtension: String = "mp4") -> String {
        // On Android, MediaFileType is String, so we can use it directly or infer from extension
        // If it's already a MIME type, return it; otherwise infer from extension
        if fileType.contains("/") {
            return fileType // Already a MIME type
        }
        // Return MIME type based on common video formats
        switch defaultExtension.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "3gp":
            return "video/3gpp"
        case "3g2":
            return "video/3gpp2"
        default:
            return "video/mp4" // Default to MPEG-4
        }
    }
    
    private nonisolated func fileExtensionString(from fileType: MediaFileType, defaultExtension: String = "mp4") -> String {
        // On Android, MediaFileType is String
        // If it's a file extension, return it; otherwise use default
        if !fileType.contains("/") && !fileType.contains(".") {
            // Looks like a simple extension
            return fileType
        }
        // Return file extension based on common video formats
        switch defaultExtension.lowercased() {
        case "mp4", "m4v", "mov", "3gp", "3g2":
            return defaultExtension
        default:
            return "mp4" // Default to MP4
        }
    }
    #elseif canImport(AVFoundation)
    private nonisolated func fileTypeString(from fileType: MediaFileType, defaultExtension: String = "mp4") -> String {
        // Extract rawValue from AVFileType on Apple platforms
        return fileType.rawValue
    }
    
    private nonisolated func fileExtensionString(from fileType: MediaFileType, defaultExtension: String = "mp4") -> String {
        // Convert AVFileType to file extension on Apple platforms
        let rawValue = fileType.rawValue
        #if canImport(UniformTypeIdentifiers)
        if let utType = UTType(rawValue) {
            if let ext = utType.preferredFilenameExtension {
                return ext
            }
        }
        #endif
        return defaultExtension
    }
    #else
    // Fallback for platforms without AVFoundation
    private nonisolated func fileTypeString(from fileType: MediaFileType, defaultExtension: String = "mp4") -> String {
        // On platforms without AVFoundation, MediaFileType is String
        return fileType
    }
    
    private nonisolated func fileExtensionString(from fileType: MediaFileType, defaultExtension: String = "mp4") -> String {
        // On platforms without AVFoundation, MediaFileType is String
        return fileType.isEmpty ? defaultExtension : fileType
    }
    #endif
    
    public enum AVAssetExportPreset: String, Sendable {
        case lowQuality = "AVAssetExportPresetLowQuality"
        case mediumQuality = "AVAssetExportPresetMediumQuality"
        case highestQuality = "AVAssetExportPresetHighestQuality"
        
        case hevcHighestQuality = "AVAssetExportPresetHEVCHighestQuality"
        case hevcHighestQualityWithAlpha = "AVAssetExportPresetHEVCHighestQualityWithAlpha"
        
        case resolution640x480 = "AVAssetExportPreset640x480"
        case resolution960x540 = "AVAssetExportPreset960x540"
        case resolution1280x720 = "AVAssetExportPreset1280x720"
        case resolution1920x1080 = "AVAssetExportPreset1920x1080"
        case resolution3840x2160 = "AVAssetExportPreset3840x2160"
        
        case hevc1920x1080 = "AVAssetExportPresetHEVC1920x1080"
        case hevc1920x1080WithAlpha = "AVAssetExportPresetHEVC1920x1080WithAlpha"
        case hevc3840x2160 = "AVAssetExportPresetHEVC3840x2160"
        case hevc3840x2160WithAlpha = "AVAssetExportPresetHEVC3840x2160WithAlpha"
        
        case hevc7680x4320 = "AVAssetExportPresetHEVC7680x4320"
        case mvhevc960x960 = "AVAssetExportPresetMVHEVC960x960"
        case mvhevc1440x1440 = "AVAssetExportPresetMVHEVC1440x1440"
        
        case appleM4A = "AVAssetExportPresetAppleM4A"
        case passthrough = "AVAssetExportPresetPassthrough"
        case appleProRes422LPCM = "AVAssetExportPresetAppleProRes422LPCM"
        case appleProRes4444LPCM = "AVAssetExportPresetAppleProRes4444LPCM"
        
        case appleM4VCellular = "AVAssetExportPresetAppleM4VCellular"
        case appleM4ViPod = "AVAssetExportPresetAppleM4ViPod"
        case appleM4V480pSD = "AVAssetExportPresetAppleM4V480pSD"
        case appleM4VAppleTV = "AVAssetExportPresetAppleM4VAppleTV"
        
        case appleM4VWiFi = "AVAssetExportPresetAppleM4VWiFi"
        case appleM4V720pHD = "AVAssetExportPresetAppleM4V720pHD"
        case appleM4V1080pHD = "AVAssetExportPresetAppleM4V1080pHD"
        
        public var targetSize: CGSize {
            switch self {
            case .lowQuality:
                return CGSize(width: 320, height: 240) // Low quality
            case .mediumQuality:
                return CGSize(width: 640, height: 360) // Medium quality
            case .highestQuality:
                return CGSize(width: 1920, height: 1080) // Highest quality (1080p)
                
            case .hevcHighestQuality:
                return CGSize(width: 3840, height: 2160) // HEVC highest quality (4K)
            case .hevcHighestQualityWithAlpha:
                return CGSize(width: 3840, height: 2160) // HEVC highest quality with alpha (4K)
                
            case .resolution640x480:
                return CGSize(width: 640, height: 480) // 640x480
            case .resolution960x540:
                return CGSize(width: 960, height: 540) // 960x540
            case .resolution1280x720:
                return CGSize(width: 1280, height: 720) // 720p
            case .resolution1920x1080:
                return CGSize(width: 1920, height: 1080) // 1080p
            case .resolution3840x2160:
                return CGSize(width: 3840, height: 2160) // 4K
                
            case .hevc1920x1080:
                return CGSize(width: 1920, height: 1080) // HEVC 1080p
            case .hevc1920x1080WithAlpha:
                return CGSize(width: 1920, height: 1080) // HEVC 1080p with alpha
            case .hevc3840x2160:
                return CGSize(width: 3840, height: 2160) // HEVC 4K
            case .hevc3840x2160WithAlpha:
                return CGSize(width: 3840, height: 2160) // HEVC 4K with alpha
                
            case .hevc7680x4320:
                return CGSize(width: 7680, height: 4320) // HEVC 8K
            case .mvhevc960x960:
                return CGSize(width: 960, height: 960) // MV HEVC 960x960
            case .mvhevc1440x1440:
                return CGSize(width: 1440, height: 1440) // MV HEVC 1440x1440
                
            case .appleM4A:
                return CGSize(width: 640, height: 480) // M4A (audio only, size not applicable)
            case .passthrough:
                return CGSize(width: 1920, height: 1080) // Passthrough (assume 1080p)
            case .appleProRes422LPCM:
                return CGSize(width: 1920, height: 1080) // ProRes 422 (assume 1080p)
            case .appleProRes4444LPCM:
                return CGSize(width: 1920, height: 1080) // ProRes 4444 (assume 1080p)
                
            case .appleM4VCellular:
                return CGSize(width: 640, height: 360) // M4V for cellular (lower resolution)
            case .appleM4ViPod:
                return CGSize(width: 640, height: 480) // M4V for iPod (standard resolution)
            case .appleM4V480pSD:
                return CGSize(width: 854, height: 480) // 480p SD
            case .appleM4VAppleTV:
                return CGSize(width: 1920, height: 1080) // M4V for Apple TV (1080p)
                
            case .appleM4VWiFi:
                return CGSize(width: 1280, height: 720) // M4V for WiFi (720p)
            case .appleM4V720pHD:
                return CGSize(width: 1280, height: 720) // 720p HD
            case .appleM4V1080pHD:
                return CGSize(width: 1920, height: 1080) // 1080p HD
            }
        }
    }
    
    /// Creates a compress Media Item for a given URL. **IMPORTANT** you need to remove the file from the tempory directory after you are finished with it.
    /// - Parameters:
    ///   - inputURL: Media URL
    ///   - presetName: The quality desired to create
    ///   - originalResolution: The original video resolution
    ///   - fileType: The media type
    ///   - outputFileType: The output file type
    /// - Throws: Potential Errors if we are experiencing an issue in the export session
    /// - Returns: The Compressed URL of the export session
    nonisolated public func compressMedia(
        inputURL: URL,
        presetName: AVAssetExportPreset,
        originalResolution: CGSize,
        fileType: MediaFileType,
        outputFileType: MediaFileType
    ) async throws -> URL {
        #if os(Android)
        // Call into SKIP-transpiled Android implementation
        // On Android, MediaFileType is String, so we can use it directly
        let inputExtension = inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension
        let fileTypeStr = fileTypeString(from: fileType, defaultExtension: inputExtension)
        let outputExtension = fileExtensionString(from: outputFileType, defaultExtension: "mp4")
        
        let androidPreset = mapToAndroidPreset(presetName)
        return try await androidCompressor.compressMedia(
            inputURL: inputURL,
            presetName: androidPreset,
            originalResolution: originalResolution,
            fileType: fileTypeStr,
            outputFileType: outputExtension
        )
        #elseif os(iOS) || os(macOS) && canImport(AVFoundation) && canImport(CoreImage)
        // Use Apple implementation
        let tempDirectory = FileManager.default.temporaryDirectory

        let outputExtension = UTType(outputFileType.rawValue)?.preferredFilenameExtension
        let outputURL = tempDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(outputExtension ?? "mp4")
        
        let asset = AVURLAsset(url: inputURL)
        
        // Check for video tracks
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw CompressionErrors.noVideoTrack
        }
        
        let targetSize = await scaledResolution(for: originalResolution, using: presetName)
        
        let videoComposition = try await createVideoComposition(
            for: asset,
            using: videoTrack,
            targetSize: targetSize)
        
        videoComposition.renderSize = targetSize
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName.rawValue) else {
            throw CompressionErrors.failedToCreateExportSession
        }
        
        exportSession.videoComposition = videoComposition
        //Strip Metadata
        exportSession.metadata = []
        
        // Start the export process
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            return outputURL
        } else if let error = exportSession.error {
            throw error
        } else {
            throw CompressionErrors.failedToCreateExportSession
        }
        #else
        throw CompressionErrors.unsupportedPlatform
        #endif
    }
    
    #if os(Android)
    /// Maps Apple AVAssetExportPreset to Android CompressionPreset
    private nonisolated func mapToAndroidPreset(_ preset: AVAssetExportPreset) -> AndroidMediaCompressor.CompressionPreset {
        switch preset {
        case .lowQuality:
            return .lowQuality
        case .mediumQuality:
            return .mediumQuality
        case .highestQuality:
            return .highestQuality
        case .resolution640x480:
            return .resolution640x480
        case .resolution960x540:
            return .resolution960x540
        case .resolution1280x720:
            return .resolution1280x720
        case .resolution1920x1080:
            return .resolution1920x1080
        case .resolution3840x2160:
            return .resolution3840x2160
        default:
            // Map HEVC and other presets to closest Android equivalent
            return .highestQuality
        }
    }
    #endif
    
    func scaledResolution(for originalSize: CGSize, using preset: MediaCompressor.AVAssetExportPreset) -> CGSize {
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
    
    #if os(iOS) || os(macOS) && canImport(AVFoundation) && canImport(CoreImage)
    nonisolated func createVideoComposition(
        for asset: AVAsset,
        using track: AVAssetTrack,
        targetSize: CGSize
    ) async throws -> AVMutableVideoComposition {
        
        return try await AVMutableVideoComposition.videoComposition(with: asset) { request in
            
            // Extract the original source image's extent
            let sourceExtent = request.sourceImage.extent
            let originalSize = CGSize(width: sourceExtent.width, height: sourceExtent.height)
            
            // Calculate scale factors along each axis and choose the lesser value
            // This maintains the original aspect ratio.
            let scaleX = targetSize.width / originalSize.width
            let scaleY = targetSize.height / originalSize.height
            let scaleFactor = min(scaleX, scaleY)
            
            // Set up the Lanczos scale transform filter.
            guard let scaleFilter = CIFilter(name: "CILanczosScaleTransform") else {
                // Finish with an empty image if the filter failed to instantiate.
                request.finish(with: CIImage(), context: nil)
                return
            }
            
            scaleFilter.setValue(request.sourceImage, forKey: kCIInputImageKey)
            scaleFilter.setValue(scaleFactor, forKey: kCIInputScaleKey)
            scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey) // Lock aspect ratio
            
            // Retrieve the filtered output image.
            guard let scaledImage = scaleFilter.outputImage else {
                // Finish the request with an empty image in case of error.
                request.finish(with: CIImage(), context: nil)
                return
            }
            
            // Compute new dimensions after scaling.
            let scaledWidth = originalSize.width * scaleFactor
            let scaledHeight = originalSize.height * scaleFactor
            
            // Center the scaled image within the adjusted target size.
            let xOffset = (targetSize.width - scaledWidth) / 2.0
            let yOffset = (targetSize.height - scaledHeight) / 2.0
            let centeringTransform = CGAffineTransform(translationX: xOffset, y: yOffset)
            let centeredImage = scaledImage.transformed(by: centeringTransform)
            
            // Provide the final composed image to finish the request.
            request.finish(with: centeredImage, context: nil)
        }
    }
    #endif
}
