//
//  CGSize+Extension.swift
//  NeedleTailMediaKit
//
//  Created by Cole M on 8/6/23.
//  Extension for CVPixelBuffer to provide width and height properties.
//

#if canImport(CoreImage)
import CoreImage

/// Extension to provide convenient width and height accessors for CVPixelBuffer.
extension CVPixelBuffer {
    /// The width of the pixel buffer.
    var width: Int {
        CVPixelBufferGetWidth(self)
    }
    /// The height of the pixel buffer.
    var height: Int {
        CVPixelBufferGetHeight(self)
    }
}
#endif
