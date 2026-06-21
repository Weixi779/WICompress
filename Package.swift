// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WICompress",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
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
            name: "WICompress",
            dependencies: [],
            path: "Sources/WICompress"
        ),
        .testTarget(
            name: "WICompressTests",
            dependencies: ["WICompress"],
            path: "Tests",
            resources: [.copy("WICompressTests/Resources")]
        ),
    ]
)
