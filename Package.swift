// swift-tools-version: 5.8
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
        swiftSettings: [
            .define("ACCELERATE_NEW_LAPACK=1")
            .define("ACCELERATE_LAPACK_ILP64=1")
        ]
        ),
        .testTarget(
            name: "needletail-media-kitTests",
            dependencies: ["NeedletailMediaKit"]),
    ]
)
