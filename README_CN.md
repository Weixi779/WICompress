# WICompress

[![CI](https://github.com/Weixi779/WICompress/actions/workflows/ci.yml/badge.svg)](https://github.com/Weixi779/WICompress/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-blue)
![Swift](https://img.shields.io/badge/Swift-6.2%2B-orange)
![SPM Support](https://img.shields.io/badge/SPM-Supported-brightgreen)
![License](https://img.shields.io/github/license/Weixi779/WICompress)

[English](README.md) | 简体中文

基于 ImageIO 与 Core Graphics，为 Swift 提供图片处理与压缩能力。输入编码后的
`Data` 或文件 `URL`，统一得到强类型 `WIResult`；Core 不依赖 UIKit 或 AppKit。

Package 发布两个可以独立使用的 library：

| Product | 职责 |
| --- | --- |
| `WICompress` | 高层 Process 与硬字节目标压缩，同时提供同步和异步 terminal。 |
| `WIImageIO` | 底层同步 inspection、decode、thumbnail、transcode 与 encode primitive。 |

## 压缩效果

下图通过 public API 和仓库真实 fixtures 生成，覆盖默认 Process、格式转换、Target
压缩、HEIC、JPEG、PNG、透明度与 passthrough 场景。

![WICompress 压缩效果对比](docs/assets/compression-comparison.png)

使用 `swift run WICompressDocAssetGenerator` 可以重新生成。

## 快速开始

WICompress 2.0 要求 Swift 6.2 / Xcode 26 以上，支持 iOS 14、macOS 11、
Mac Catalyst 14、tvOS 14、watchOS 7 与 visionOS 1 以上。

```swift
dependencies: [
    .package(url: "https://github.com/Weixi779/WICompress.git", from: "2.0.0")
]
```

应用 target 通常选择高层 `WICompress` product；只需要底层 primitive 时，将其换成
`WIImageIO`：

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "WICompress", package: "WICompress")
    ]
)
```

应用明确操作内容时使用 **Process**。最终字节数是结果，不是承诺：

```swift
import WICompress

let result = try await WICompressor.process(imageData)
```

所有成功结果都必须满足硬字节上限时使用 **Target**：

```swift
let result = try await WICompressor.compress(
    imageData,
    to: WICompressionTarget(maxBytes: 500_000)
)
```

| | Process | Target |
| --- | --- | --- |
| Terminal | `WICompressor.process` | `WICompressor.compress` |
| 调用方声明 | Crop、resizing、quality 与 output。 | `maxBytes`、可选基础 geometry 与 output。 |
| 库控制 | 执行路径。 | 候选 quality 与尺寸。 |
| 字节保证 | 无。 | `result.byteCount <= maxBytes`。 |
| 默认输出 | 保持源 representation。 | 含 alpha 时 PNG，否则 JPEG。 |

两条路径都通过 `WIResult` 返回编码 `data`、`format`、整数 `pixelSize` 与
`byteCount`。每个 Data/file terminal 同时提供同步 overload。

### 常见上传配置

```swift
let upload = try await WICompressor.process(
    imageData,
    using: WIImageProcess(
        sizing: .resize(using: WIImageResize.maximumPixelSize(1_600)),
        quality: 0.7,
        output: WIImageOutput(
            representation: .jpeg(background: .white),
            metadata: .strip,
            colorSpace: .convert(to: .sRGB)
        )
    )
)
```

JPEG 转换不会静默丢弃透明度。需要明确选择 `.white`、`.black`，或调用方提供的
不透明 `.color(...)` 背景。

## 直接使用 WIImageIO

真正需要 typed ImageIO 操作时，选择独立的 `WIImageIO` product：

```swift
import UniformTypeIdentifiers
import WIImageIO

let reader = try ImageReader(imageData)
let descriptor = reader.descriptor

let encoded = try reader
    .thumbnail(options: .init(maximumPixelSize: 1_200))
    .encode(
        as: .jpeg,
        options: .init(compressionQuality: 0.75)
    )
```

API 不暴露 `CGImageSource`、`CGImageDestination`、properties 字典或全局 coder
registry。WIImageIO 保持同步，调度由调用方拥有。

## Example 与 Benchmark

[SwiftUI Example](Example/WICompressExample) 展示 `PhotosPicker`、源图 inspection、
异步 Process/Target、cooperative cancellation 与处理前后事实：

```bash
open Example/WICompressExample/WICompressExample.xcodeproj
```

仓库还提供 Target 压缩的 Release-mode developer benchmark；它不是公开 package
product：

```bash
swift run -c release TargetCompressionBenchmark
```

固定 corpus、质量指标和 baseline/candidate 比较方式见
[Benchmark 指南](benchmarks/target-compression/README_CN.md)。

## 文档

- [WICompress DocC](Sources/WICompress/Documentation.docc/WICompress.md)
- [WIImageIO DocC](Sources/image/io/WIImageIO.docc/WIImageIO.md)
- [架构](docs/architecture/README_CN.md)
- [迁移到 2.0](docs/guides/MIGRATION_2_CN.md)
- [Changelog](CHANGELOG.md)

异步取消是 cooperative 的，并保持标准 `CancellationError`；处理失败使用
`WICompressError`。完整行为与 API 示例见 DocC 指南。

## License

WICompress 基于 Apache-2.0 许可证开源，详情见 [LICENSE.txt](LICENSE.txt)。
