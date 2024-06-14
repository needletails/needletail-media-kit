#if os(macOS) || os(iOS)
//Copyright © 2023 Apple Inc.
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Accelerate

@globalActor public actor MatrixActor {
    public static let shared = MatrixActor()
    public init() {}
}

/// A basic single-precision matrix object.
public struct Matrix: Sendable {
    /// The number of rows in the matrix.
    public let rowCount: Int
    
    /// The number of columns in the matrix.
    public let columnCount: Int
    
    /// The total number of elements in the matrix.
    public var count: Int {
        return rowCount * columnCount
    }
    
    /// A pointer to the matrix's underlying data.
    public var data: UnsafeMutableBufferPointer<Float> {
        get {
            return dataReference.data
        }
        set {
            dataReference.data = newValue
        }
    }

    /// A pointer to the matrix's underlying data reference.
    private var dataReference: MatrixDataReference
    
    /// An object that wraps the structure's data and provides deallocation when the code releases the structure.
    private final class MatrixDataReference: @unchecked Sendable {
        var data: UnsafeMutableBufferPointer<Float>
        
        init(data: UnsafeMutableBufferPointer<Float>) {
            self.data = data
        }
        
        deinit {
            self.data.deallocate()
        }
    }
}



/// Extension to create a matrix from an image and an image from a matrix.
extension Matrix {
    
    /// The 32-bit planar image format that the `Matrix` type uses to
    /// consume and produce `CGImage` instances.
    @MatrixActor private static var imageFormat = vImage_CGImageFormat(
        bitsPerComponent: 32,
        bitsPerPixel: 32,
        colorSpace: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue:
                                 kCGBitmapByteOrder32Host.rawValue |
                                 CGBitmapInfo.floatComponents.rawValue |
                                 CGImageAlphaInfo.none.rawValue))!
    
    /// Converts the specified image to 32-bit planar and returns a new matrix
    /// that contains that image data.
    @MatrixActor public init?(cgImage: CGImage) {
        
        self.init(rowCount: cgImage.height,
                  columnCount: cgImage.width)
        
        // Create a `vImage_Buffer` that shares data with `self`.
        var tmpBuffer = vImage_Buffer(
            data: self.data.baseAddress,
            height: vImagePixelCount(self.rowCount),
            width: vImagePixelCount(self.columnCount),
            rowBytes: self.columnCount * MemoryLayout<Float>.stride)
        
        let error = vImageBuffer_InitWithCGImage(
            &tmpBuffer,
            &Matrix.imageFormat,
            [0, 0, 0, 0],
            cgImage,
            vImage_Flags(kvImageNoAllocate))
        
        if error != kvImageNoError {
            return nil
        }
    }
    
    /// Returns a 32-bit per pixel, grayscale `CGImage`instance of the matrix's data.
    @MatrixActor public var cgImage: CGImage? {
        
        let tmpBuffer = vImage_Buffer(
            data: self.data.baseAddress!,
            height: vImagePixelCount(self.rowCount),
            width: vImagePixelCount(self.columnCount),
            rowBytes: self.columnCount * MemoryLayout<Float>.stride)
        
        return try? tmpBuffer.createCGImage(format: Matrix.imageFormat)
    }
}

/// Properties for BLAS and LAPACK interoperability.
extension Matrix {
    /// The number of rows as a 32-bit integer.
    public var m: Int32 {
        return Int32(rowCount)
    }
    
    /// The number of columns as a 32-bit integer.
    public var n: Int32 {
        return Int32(columnCount)
    }
    
    /// The minimum dimension of the matrix.
    public var minimumDimension: Int {
        return min(rowCount, columnCount)
    }
}

/// Static allocation functions.
extension Matrix {

    /// Returns a zero-filled matrix.
    public init(rowCount: Int,
                columnCount: Int) {
        
        let count = rowCount * columnCount
        
        let start = UnsafeMutablePointer<Float>.allocate(capacity: count)
        
        let buffer = UnsafeMutableBufferPointer(start: start,
                                                count: count)
        buffer.initialize(repeating: 0)
        
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.dataReference = MatrixDataReference(data: buffer)
    }
    
    /// Returns a column-major matrix with the specified diagonal elements.
    public init<C>(diagonal: C,
                   rowCount: Int,
                   columnCount: Int)
    where
    C: Collection,
    C.Index == Int,
    C.Element == Float {
        
        self.init(rowCount: rowCount,
                  columnCount: columnCount)
        
        for i in 0 ..< min(rowCount, columnCount, diagonal.count) {
            self[i * rowCount + i] = diagonal[i]
        }
    }
}

/// Subscript access.
extension Matrix {
    /// Accesses the element at the specified index.
    public subscript(index: Int) -> Float {
        get {
            assert(index < dataReference.data.count, "Index out of range")
            return dataReference.data[index]
        }
        set {
            assert(index < dataReference.data.count, "Index out of range")
            dataReference.data[index] = newValue
        }
    }
    
    private func indexIsValid(row: Int, column: Int) -> Bool {
        return row >= 0 && row < rowCount && column >= 0 && column < columnCount
    }
    
    /// Accesses the element at the specified row and column.
    public subscript(row: Int, column: Int) -> Float {
        get {
            assert(indexIsValid(row: row, column: column), "Index out of range")
            return dataReference.data[(row * columnCount) + column]
        }
        set {
            assert(indexIsValid(row: row, column: column), "Index out of range")
            dataReference.data[(row * columnCount) + column] = newValue
        }
    }
}

extension Matrix: CustomStringConvertible {
    /// A textual representation of this instance.
    public var description: String {
        var returnString = ""
        for y in 0 ..< rowCount {
            var str = ""
            for x in 0 ..< columnCount {
                str += String(format: "%.2f ", self[y, x])
            }
            returnString += str + "\n"
        }
        return returnString
    }
}
#endif
