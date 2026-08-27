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
    targets: [
        .executableTarget(
            name: "BackgroundRemoverApp",
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
