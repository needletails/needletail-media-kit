//
//  CGInterpolationQuality+Linux.swift
//  NeedleTailMediaKit
//
//  Linux compatibility shim.
//

#if os(Linux)

/// `CGInterpolationQuality` is normally provided by CoreGraphics, which isn't
/// available on Linux in SwiftPM by default.
///
/// We only need this to satisfy type references in shared APIs; the Linux
/// implementation currently falls back to a no-op/unsupported implementation.
public enum CGInterpolationQuality: Int, Sendable {
    case `default` = 0
    case none = 1
    case low = 2
    case medium = 4
    case high = 8
}

#endif
