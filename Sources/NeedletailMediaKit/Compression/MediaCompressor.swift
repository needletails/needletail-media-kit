//
//  MediaCompression.swift
//  needletail-media-kit
//
//  Created by Cole M on 8/25/24.
//
#if os(iOS) || os(macOS)
import AVFoundation

public actor MediaCompressor {
    
    public init() {}
    
    enum CompressionErrors: Error {
        case failedToCreateExportSession
    }
    
    public enum AVAssetExportPreset: String {
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
    }
    
    
    /// Creates a compress Media Item for a given URL. **IMPORTANT** you need to remove the file from the tempory directory after you are finished with it.
    /// - Parameters:
    ///   - inputURL: Media URL
    ///   - presetName: The quality desired to create
    ///   - fileType: The media type
    /// - Throws: Potential Errors if we are experiencing an issue in the export session
    /// - Returns: The Compressed URL of the export session
    public func compressMedia(inputURL: URL, presetName: AVAssetExportPreset, fileType: AVFileType) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileType.rawValue)
        
        let asset = AVAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName.rawValue) else {
            throw CompressionErrors.failedToCreateExportSession
        }
        if #available(iOS 18, macOS 15, *) {
            try await exportSession.export(to: outputURL, as: .mov, isolation: self)
        } else {
            exportSession.outputURL = outputURL
            exportSession.outputFileType = fileType
            await exportSession.export()
        }
        return outputURL
    }
    
    
}
#endif
