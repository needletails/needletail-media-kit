#if os(macOS) || os(iOS)
//Copyright © 2023 Apple Inc.
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Accelerate

@available(iOS 16.4, macOS 13.3, *)
extension Matrix {
    
    /// Calculates `CblasColMajor` matrix multiply, `c = a * b`.
    ///
    /// - Parameter a: The `a`  in  `c = a * b`.
    /// - Parameter b: The `b`  in  `c = a * b`.
    /// - Parameter c: The `c`  in  `c = a * b`.
    /// - Parameter k: Override for the number of columns in matrix _A_ and number of rows in matrix _B_.
    public static func multiply(a: Matrix,
                                b: Matrix,
                                c: Matrix,
                                k: Int32? = nil) {

        cblas_sgemm(CblasColMajor,
                    CblasNoTrans, CblasNoTrans,
                    a.m,
                    b.n,
                    k ?? b.m,
                    1,
                    a.data.baseAddress, a.m,
                    b.data.baseAddress, b.m,
                    0,
                    c.data.baseAddress, c.m)
    }
}
#endif

