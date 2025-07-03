//
//  CVPixelBuffer+Extension.swift
//  NeedleTail
//
//  Created by Cole M on 8/6/23.
//

#if os(macOS) || os(iOS)
import CoreImage

extension CVPixelBuffer {
    var width: Int {
        CVPixelBufferGetWidth(self)
    }
    
    var height: Int {
        CVPixelBufferGetHeight(self)
    }
}
#endif
