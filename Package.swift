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
            name: "WIImageDomain",
            dependencies: [],
            path: "Sources/domain"
        ),
        .target(
            name: "WIImageIO",
            dependencies: ["WIImageDomain"],
            path: "Sources/imageio"
        ),
        .target(
            name: "WIImageRaster",
            dependencies: ["WIImageDomain"],
            path: "Sources/raster"
        ),
        .target(
            name: "WICompressExecution",
            dependencies: ["WIImageDomain", "WIImageIO", "WIImageRaster"],
            path: "Sources/execution"
        ),
        .target(
            name: "WICompress",
            dependencies: ["WIImageDomain", "WIImageIO", "WICompressExecution"],
            path: "Sources/WICompress"
        ),
        .testTarget(
            name: "WIImageDomainTests",
            dependencies: ["WIImageDomain"],
            path: "Tests/WIImageDomainTests"
        ),
        .testTarget(
            name: "WIImageIOTests",
            dependencies: ["WIImageDomain", "WIImageIO"],
            path: "Tests/WIImageIOTests"
        ),
        .testTarget(
            name: "WIImageRasterTests",
            dependencies: ["WIImageDomain", "WIImageRaster"],
            path: "Tests/WIImageRasterTests"
        ),
        .testTarget(
            name: "WICompressTests",
            dependencies: ["WICompress", "WICompressExecution", "WIImageDomain", "WIImageIO"],
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
