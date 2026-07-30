// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WICompress",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .macCatalyst(.v14),
        .tvOS(.v14),
        .watchOS(.v7),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "WICompress",
            targets: ["WICompress"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WIImageCore",
            dependencies: [],
            path: "Sources/WIImageCore"
        ),
        .target(
            name: "WIImageIO",
            dependencies: ["WIImageCore"],
            path: "Sources/WIImageIO"
        ),
        .target(
            name: "WIImageRaster",
            dependencies: ["WIImageCore"],
            path: "Sources/WIImageRaster"
        ),
        .target(
            name: "WICompress",
            dependencies: ["WIImageCore", "WIImageIO", "WIImageRaster"],
            path: "Sources/WICompress"
        ),
        .testTarget(
            name: "WIImageCoreTests",
            dependencies: ["WIImageCore"],
            path: "Tests/WIImageCoreTests"
        ),
        .testTarget(
            name: "WIImageIOTests",
            dependencies: ["WIImageCore", "WIImageIO"],
            path: "Tests/WIImageIOTests"
        ),
        .testTarget(
            name: "WIImageRasterTests",
            dependencies: ["WIImageCore", "WIImageRaster"],
            path: "Tests/WIImageRasterTests"
        ),
        .testTarget(
            name: "WICompressTests",
            dependencies: ["WICompress", "WIImageCore"],
            path: "Tests/WICompressTests",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "WICompressDocAssetGenerator",
            dependencies: ["WICompress"],
            path: "scripts",
            sources: ["generate-doc-assets.swift"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
