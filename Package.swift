// swift-tools-version:5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "needletail-media-kit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NeedletailMediaKit",
            targets: ["NeedletailMediaKit"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NeedletailMediaKit",
            resources: [.process("Sources/NeedletailMediaKit/MetalProcessor/Shaders/MetalShaders.metal")]
        ),
        .testTarget(
            name: "needletail-media-kitTests",
            dependencies: ["NeedletailMediaKit"]),
    ]
)

#if os(iOS) || os(macOS)
package.dependencies.append(.package(url: "https://github.com/stasel/WebRTC.git", .upToNextMajor(from: "126.0.0")))
package.targets.first(where: { $0.name == "SpineTailedKit" })?.dependencies.append(.product(name: "WebRTC", package: "WebRTC"))
#endif
