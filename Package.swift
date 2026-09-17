// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NeedleTailMediaKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        // Default automatic (static) product so dependents like nudge-kit can
        // `swift test` without SPM duplicate-symbol failures:
        //   NeedleTailLogger-product / Logging-product linked by both
        //   NudgeKitTests-product and NeedleTailMediaKit-product.
        // Skip Android needs a dylib; flip to .dynamic only when SKIP_BRIDGE=1
        // (same pattern as pqs-rtc).
        .library(
            name: "NeedleTailMediaKit",
            targets: ["NeedleTailMediaKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.6"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.4.5"),
        .package(url: "https://github.com/needletails/needletail-logger.git", from: "3.1.5")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NeedleTailMediaKit",
            dependencies: [
                .product(name: "SkipFoundation", package: "skip-foundation"),
                .product(name: "NeedleTailLogger", package: "needletail-logger")
            ],
            resources: [
                .process("MetalProcessor/Shaders/ImageShaders.metal"),
                .process("Resources")
            ],
            plugins: [
                .plugin(name: "skipstone", package: "skip")
            ]
        ),
        .testTarget(
            name: "NeedleTailMediaKitTests",
            dependencies: ["NeedleTailMediaKit",  .product(name: "SkipTest", package: "skip")],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)


#if os(iOS) || os(macOS) && !os(Android) && !os(Linux)
package.dependencies.append(.package(url: "https://github.com/needletails/Specs.git", from: "144.7559.04"))
package.targets.first(where: { $0.name == "NeedleTailMediaKit" })?.dependencies.append(.product(name: "WebRTC", package: "Specs"))
#endif

let skipBridge = (Context.environment["SKIP_BRIDGE"] ?? "0") != "0"
if skipBridge {
    package.products = package.products.map { product in
        guard let libraryProduct = product as? Product.Library else { return product }
        return .library(
            name: libraryProduct.name,
            type: .dynamic,
            targets: libraryProduct.targets)
    }
}
