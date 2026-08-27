// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BackgroundRemover",
    defaultLocalization: "es",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BackgroundRemover",
            targets: ["BackgroundRemover"]
        ),
        .executable(
            name: "BackgroundRemoverApp",
            targets: ["BackgroundRemover"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "BackgroundRemover",
            dependencies: [],
            path: "Sources/BackgroundRemover"
        ),
        .testTarget(
            name: "BackgroundRemoverTests",
            dependencies: ["BackgroundRemover"],
            path: "Tests/BackgroundRemoverTests"
        )
    ]
)
