// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "superscribe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SuperscribeKit", targets: ["SuperscribeKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.14.3"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "SuperscribeKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .executableTarget(
            name: "superscribe",
            dependencies: [
                "SuperscribeKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "superscribeTests",
            dependencies: ["SuperscribeKit"]
        )
    ]
)
