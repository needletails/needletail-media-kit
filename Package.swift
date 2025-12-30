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
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NeedleTailMediaKit",
            type: .dynamic,
            targets: ["NeedleTailMediaKit"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.6.32"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.3.10")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NeedleTailMediaKit",
            dependencies: [
                .product(name: "SkipFoundation", package: "skip-foundation")
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

#if os(iOS) || os(macOS) && !os(Android)
package.dependencies.append(.package(url: "https://github.com/needletails/Specs.git", from: "137.7151.11"),)
package.targets.first(where: { $0.name == "NeedleTailMediaKit" })?.dependencies.append(.product(name: "WebRTC", package: "Specs"))
#endif
