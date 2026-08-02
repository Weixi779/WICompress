# 迁移到 WICompress 2.0

[English](MIGRATION_2.md)

WICompress 2.0 是一次有意的 breaking release。需要继续使用 1.x API，或工具链低于
Swift 6.2 的项目，应停留在最新 1.x 版本。

## 系统要求

WICompress 2.0 要求 Swift 6.2，并使用 Swift 6 language mode。Deployment target
仍为 iOS 14、macOS 11、Mac Catalyst 14、tvOS 14、watchOS 7 与 visionOS 1 以上。

Package 与高层 product 仍叫 `WICompress`：

```swift
import WICompress
```

Package 还发布独立的 `WIImageIO` product，用于底层 ImageIO 操作。

## Terminal namespace

高层静态 terminal 从 `WICompress` 移到 `WICompressor`：

| 1.x | 2.0 |
| --- | --- |
| `WICompress.compress(_:options:)` | `WICompressor.process(_:using:)` |
| `WICompress.compress(contentsOf:options:)` | `WICompressor.process(contentsOf:using:)` |
| `WICompress.compress(_:to:)` | `WICompressor.compress(_:to:)` |
| `WICompress.compress(contentsOf:to:)` | `WICompressor.compress(contentsOf:to:)` |

`WICompressor` 是不可实例化的 namespace。2.0 不提供 `.shared` 单例、deprecated
wrapper 或兼容 alias。

## 替换 Options 与 Policy

2.0 不再保留 1.x Policy。根据结果合同选择 API：

- 调用方明确 crop、resizing、quality 与 output 时，使用 `WIImageProcess`。
- 最终编码数据必须不超过 `maxBytes` 时，使用 `WICompressionTarget`。

```swift
let processed = try WICompressor.process(
    imageData,
    using: WIImageProcess(
        sizing: .resize(using: WIImageResize.maximumPixelSize(1_600)),
        quality: 0.7
    )
)

let constrained = try WICompressor.compress(
    imageData,
    to: WICompressionTarget(maxBytes: 500_000)
)
```

Process 与 Target 都返回 `WIResult`。原先直接接收 `Data` 的位置改为读取
`result.data`；格式、像素尺寸和字节数来自同一个结果。

## 默认 resizing

默认 Process sizing 已升级为 `WIImageResize.lubanV2`。它会更完整地保留普通长截图，
同时限制极端全景图和超大像素输入。需要继续使用 WICompress 修正版 Luban 1 尺寸时，
显式选择：

```swift
let process = WIImageProcess(
    sizing: .resize(using: WIImageResize.luban)
)
```

两个算法都不拥有 quality、output representation、metadata 或 target bytes。

## Output 与 metadata

Process 与 Target 共用 `WIImageOutput`，但默认值有意不同：

- Process 保留源 representation 与色彩语义，剥离 metadata，并在格式支持有损质量时
  使用 `0.6`。
- Target 剥离 metadata，把渲染结果转换为 sRGB，并按 alpha 选择 PNG，否则 JPEG。

JPEG 输出不再偷偷铺底。透明图必须明确选择不透明背景：

```swift
let output = WIImageOutput(
    representation: .jpeg(background: .white)
)
```

Metadata 使用 `ImageMetadataOptions` 选择，包括易读的 `.strip`、`.preserve`，以及
独立的 Exif、GPS、IPTC、TIFF 与 maker-note flags。

## 同名异步 overload 迁移

Data/file 的 Process/Target terminal 都有同名 async overload：

```swift
let result = try await WICompressor.process(imageData)
let thumbnail = try await WICompressor.compress(imageData, to: target)
```

在 async 上下文中，Swift 会优先解析同名的 async overload。1.x 中没有写 `await`
的同步调用在升级后会直接编译失败；需要异步执行时应增加 `await`。如果确实要调用
同步 terminal，应把它放在非 async helper 中，或显式绑定同步函数 overload；不能通过在
async function 中省略 `await` 来选择同步实现。

同步 overload 保持 typed `throws(WICompressError)`。异步 overload 使用普通
`async throws`：图片处理失败仍是 `WICompressError`，结构化任务取消仍是
`CancellationError`。取消在 Pipeline Stage 与 Target 尝试之间观察；已经进入
ImageIO 或 Core Graphics 的单次调用可能先执行完成。

## 架构参考

当前模块与执行所有权见 [2.0 架构](../architecture/README_CN.md)。
