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
