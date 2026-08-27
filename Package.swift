// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BackgroundRemover",
    defaultLocalization: "es",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "BackgroundRemoverApp",
            targets: ["BackgroundRemoverApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager.git", exact: "1.18.0")
    ],
    targets: [
        .executableTarget(
            name: "BackgroundRemoverApp",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")
            ],
            path: "Sources/BackgroundRemover",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "BackgroundRemoverTests",
            dependencies: ["BackgroundRemoverApp"],
            path: "Tests/BackgroundRemoverTests"
        )
    ]
)
