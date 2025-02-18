// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "needletail-media-kit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NeedleTailMediaKit",
            targets: ["NeedleTailMediaKit"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NeedleTailMediaKit"
//            resources: [.process("Sources/NeedleTailMediaKit/MetalProcessor/Shaders/ImageShaders.metal")]
        ),
        .testTarget(
            name: "needletail-media-kitTests",
            dependencies: ["NeedleTailMediaKit"]),
    ]
)

#if os(iOS) || os(macOS)
package.dependencies.append(.package(url: "https://github.com/stasel/WebRTC.git", .upToNextMajor(from: "130.0.0")))
package.targets.first(where: { $0.name == "NeedleTailMediaKit" })?.dependencies.append(.product(name: "WebRTC", package: "WebRTC"))
#endif
