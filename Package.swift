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
            name: "WIImageIO",
            dependencies: [],
            path: "Sources/WIImageIO"
        ),
        .target(
            name: "WICompress",
            dependencies: ["WIImageIO"],
            path: "Sources/WICompress"
        ),
        .testTarget(
            name: "WIImageIOTests",
            dependencies: ["WIImageIO"],
            path: "Tests/WIImageIOTests"
        ),
        .testTarget(
            name: "WICompressTests",
            dependencies: ["WICompress"],
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
