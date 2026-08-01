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
        .library(
            name: "WIImageIO",
            targets: ["WIImageIO"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WIImageDomain",
            dependencies: [],
            path: "Sources/image/domain"
        ),
        .target(
            name: "WICompressDomain",
            dependencies: ["WIImageDomain"],
            path: "Sources/compress/domain"
        ),
        .target(
            name: "WIImageIO",
            dependencies: ["WIImageDomain"],
            path: "Sources/image/io"
        ),
        .target(
            name: "WIImageRaster",
            dependencies: ["WIImageDomain"],
            path: "Sources/image/raster"
        ),
        .target(
            name: "WICompressExecution",
            dependencies: [
                "WIImageDomain",
                "WICompressDomain",
                "WIImageIO",
                "WIImageRaster"
            ],
            path: "Sources/compress/execution"
        ),
        .target(
            name: "WICompress",
            dependencies: [
                "WIImageDomain",
                "WICompressDomain",
                "WICompressExecution"
            ],
            path: "Sources/WICompress"
        ),
        .testTarget(
            name: "WIImageDomainTests",
            dependencies: ["WIImageDomain"],
            path: "Tests/WIImageDomainTests"
        ),
        .testTarget(
            name: "WICompressDomainTests",
            dependencies: ["WIImageDomain", "WICompressDomain"],
            path: "Tests/WICompressDomainTests"
        ),
        .testTarget(
            name: "WIImageIOTests",
            dependencies: ["WIImageIO"],
            path: "Tests/WIImageIOTests"
        ),
        .testTarget(
            name: "WIImageRasterTests",
            dependencies: ["WIImageDomain", "WIImageRaster"],
            path: "Tests/WIImageRasterTests"
        ),
        .testTarget(
            name: "WICompressTests",
            dependencies: [
                "WICompress",
                "WICompressDomain",
                "WICompressExecution",
                "WIImageDomain",
                "WIImageIO"
            ],
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
