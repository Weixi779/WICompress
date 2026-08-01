# WICompress

[![CI](https://github.com/Weixi779/WICompress/actions/workflows/ci.yml/badge.svg)](https://github.com/Weixi779/WICompress/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-blue)
![Swift](https://img.shields.io/badge/Swift-6.2%2B-orange)
![SPM Support](https://img.shields.io/badge/SPM-Supported-brightgreen)
![License](https://img.shields.io/github/license/Weixi779/WICompress)

[English](README.md) | 简体中文

用一组简单、可预测的 Swift API 完成上传前图片压缩。

`WICompress` 是一个基于 ImageIO 的 Swift 图片压缩库，直接处理原始图片
`Data` 或文件 `URL`。底层由 ImageIO 负责格式识别、方向、alpha、metadata、
色彩 profile、缩放和编码；public API 保持简单，统一返回 `WIResult`。

默认保留 JPEG / PNG / HEIC 源格式，也可以在上传端要求固定容器时显式转成
JPEG、PNG 或 HEIC，或者按 alpha 通道自动选择 PNG / JPEG；默认剥离隐私
metadata，并且不依赖 `UIImage` / `NSImage`。

```swift
let result = try WICompressor.process(originalData)
```

```swift
let uploadData = try WICompressor.process(
    originalData,
    using: WIImageProcess(
        sizing: .resize(using: WIImageResize.maximumPixelSize(1600)),
        quality: 0.7,
        output: WIImageOutput(
            representation: .jpeg(background: .white),
            metadata: .strip,
            colorSpace: .convert(to: .sRGB)
        )
    )
).data
```

## 为什么用 WICompress

- **Data in, structured result out**：保留相册、文件或网络拿到的原始字节，
  从 `WIResult` 获取编码数据、格式、像素尺寸和字节数。
- **适合上传的默认值**：Luban resize、metadata strip、JPEG/HEIC 有损质量。
- **目标约束压缩**：当 SDK 或后端要求明确字节上限时，可以用 `maxBytes`
  搭配 geometry 表达目标。
- **处理过程可组合**：crop、resizing、quality 和 output 是
  `WIImageProcess` 中彼此独立的部分。
- **格式可控**：默认保持源格式，也可以显式输出 JPEG、PNG、HEIC，或按 alpha
  通道有无选择 PNG / JPEG。
- **透明图转 JPEG 更安全**：必须显式选择白底或黑底，不会偷偷铺底。
- **方向安全**：基于 ImageIO 读取展示尺寸，redraw path 会把方向烘焙进像素。
- **核心不依赖 UIKit / AppKit**：可在 iOS App、macOS 工具和 SwiftPM 测试中使用。
- **强类型错误**：失败通过 `WICompressError` 表达，不再返回可空 `Data?`。

## 系统要求与安装

- iOS 14+ / macOS 11+ / Mac Catalyst 14+ / tvOS 14+ / watchOS 7+ / visionOS 1+
- Swift 6.2+（Xcode 26+）

通过 Swift Package Manager 集成：

```swift
dependencies: [
    .package(url: "https://github.com/Weixi779/WICompress.git", from: "2.0.0")
]
```

Package 发布两个 library product：压缩场景使用 `WICompress`；只有在确实需要底层
typed ImageIO 链路时才直接依赖 `WIImageIO`。

## 压缩效果预览

下面这张对比图由 `scripts/generate-doc-assets.swift` 基于仓库内的真图
fixtures 生成。后续压缩行为变化时，可以重新生成这张图。

```bash
swift run WICompressDocAssetGenerator
```

![WICompress 压缩效果对比](docs/assets/compression-comparison.png)

图里大多数行使用默认 API，同时包含一行用显式 `WICompressionTarget` 生成的
target API 分享缩略图示例。前三行优先展示 HEIC，因为这是最值得被用户看到的
真实场景；后面再展示 JPEG 和 PNG。PNG 不是被跳过：长截图触发 Luban resize
后会变小，而 alpha PNG 这一行只是 no-op case，原图本身已经是更好的结果。

## 示例项目

仓库包含 SwiftUI 示例项目：

1. 打开 `Example/WICompressExample/WICompressExample.xcodeproj`。
2. 在 iOS 设备或模拟器上运行。
3. 从相册选择图片，比较原始 data 和压缩后 data。

示例覆盖：

- `PhotosPicker` 和 `PHPickerViewController` 获取原始图片 `Data`
- `WICompressor.process(_:)` 处理
- 格式检测
- 原图 / 压缩图预览
- 文件大小和压缩比展示

## API 示例

```swift
import WICompress

let result = try WICompressor.process(originalData)
```

压缩文件 URL：

```swift
let result = try WICompressor.process(contentsOf: imageURL)
```

显式配置：

```swift
let result = try WICompressor.process(
    originalData,
    using: WIImageProcess(
        sizing: .resize(using: WIImageResize.luban),
        quality: 0.7,
        output: WIImageOutput(
            representation: .preserve,
            metadata: .strip,
            colorSpace: .preserve
        )
    )
)
```

在一次操作中裁剪和调整像素尺寸：

```swift
let asset = try WICompressor.process(
    originalData,
    using: WIImageProcess(
        sizing: .resize(
            using: WIImageResize.constrained(
                within: WIPixelSize(width: 400, height: 467)
            )
        ),
        crop: .aspectRatio(width: 1, height: 1),
        quality: 0.7,
        output: WIImageOutput(
            representation: .pngIfAlphaOtherwiseJPEG
        )
    )
)
```

压缩到明确的字节目标：

```swift
let thumbnail = try WICompressor.compress(
    originalData,
    to: WICompressionTarget(
        maxBytes: 32 * 1024,
        sizing: WICompressionSizing(
            maximumPixelSize: 200,
            aspectRatio: WIAspectRatio(width: 1, height: 1)
        ),
        output: WIImageOutput(
            representation: .jpeg(background: .white),
            metadata: .strip,
            colorSpace: .convert(to: .sRGB)
        )
    )
)

print(thumbnail.byteCount)
print(thumbnail.pixelSize)
```

## 底层 ImageIO 能力

`WIImageIO` 是独立的同步 product，提供 inspect、decode、thumbnail、source transcode 和
encode，同时不暴露 `CGImageSource`、`CGImageDestination` 与 properties 字典：

```swift
import WIImageIO

let reader = try ImageReader(originalData)
let descriptor = reader.descriptor

let encoded = try reader
    .thumbnail(options: .init(maximumPixelSize: 1200))
    .encode(
        as: .jpeg,
        options: .init(compressionQuality: 0.75)
    )
```

只要 options 允许，这条链会保留来源 metadata 和 orientation。它抛出
`ImageIOError`；执行线程和 actor 切换仍由调用方决定。

完整的底层入口见 [WIImageIO 使用指南](Sources/image/io/WIImageIO.docc/WIImageIO.md)。

## 和 UIKit / AppKit 一起使用

`WICompress` 不接收 `UIImage` 或 `NSImage`。业务层应该保留从相册、文件、
网络或数据库拿到的原始图片 `Data`，把这份 `Data` 传给 `WICompressor`。如果
UI 需要预览，再在边界处把压缩结果解码成 `UIImage` / `NSImage`。

```swift
guard let originalData = try await photosPickerItem.loadTransferable(type: Data.self) else {
    throw MyError.missingImageData
}

let result = try WICompressor.process(originalData)
let previewImage = UIImage(data: result.data)
```

这样调用方不需要同时传入「渲染后的图片」和「原始格式数据」。ImageIO 可以
直接从原始字节读取格式、尺寸、方向和 metadata。

## Image Process

`WIImageProcess` 描述一次确定性的图片处理。默认使用 Luban resize、`0.6`
quality、保持源容器、移除 metadata，并保留源图色彩语义。

```swift
public struct WIImageProcess {
    public let sizing: WIImageSizing
    public let crop: WIImageCrop?
    public let quality: Double?
    public let output: WIImageOutput
}
```

Sizing 刻意只保留两条分支：保留当前像素尺寸，或者交给一个
`WIImageResizing` 实现返回完整目标尺寸。内置算法包括 `luban`、
`maximumPixelSize`、`constrained`、`scaled` 和 `exact`。尺寸受业务规则
控制时，应用可以自行实现 `WIImageResizing`。

Crop 是可选的宽高比与归一化 `WICropAnchor`，先于 resizing 解析。Output
独立声明 representation（保持源容器、JPEG、PNG、HEIC、按 Alpha 选择
PNG/JPEG）、metadata（strip / preserve）和 color space（preserve /
convert）。

Quality 对有损输出使用固定的 `0...1` 值；传 `nil` 表示不显式设置 ImageIO
quality。PNG 始终无损。透明源图转换为 JPEG 时必须显式选择
`WIJPEGBackground`。

## Target Compression

`WICompressionTarget` 用来表达“输出必须满足某个目标契约”的压缩，例如
“缩略图 data 必须小于 32KB”。它与 Process 不同：quality、尺寸和尝试次数
由压缩器在内部控制。

```swift
public struct WICompressionTarget {
    public let maxBytes: Int
    public let sizing: WICompressionSizing
    public let output: WIImageOutput
}

public struct WICompressionSizing {
    public let maximumPixelSize: Int?
    public let aspectRatio: WIAspectRatio?
    public let anchor: WICropAnchor
}
```

Target 默认输出会在源图含 Alpha 时写 PNG，否则写 JPEG；同时移除 metadata 并将像素
转换到 sRGB。显式传入 `WIImageOutput` 时，以调用方声明的要求为准。

Sizing 只定义 byte search 开始前的 base candidate：

- 不传参数：从源图的 oriented display pixel size 开始。
- 只传 `maximumPixelSize`：保持源比例并限制最长边；不会放大。
- 只传 `aspectRatio`：按 `anchor` 取得该比例的最大内接裁剪。
- 两者都传：先裁剪，再限制最长边。

`anchor` 使用左上原点的 `0...1` 归一化坐标，默认居中。比例和裁剪区域解析一次后
保持不变；solver 只搜索统一缩放比例与有损 quality。JPEG 和 HEIC 会先搜索 quality，
必要时再缩小尺寸；PNG 保持无损并通过缩小尺寸满足限制。若不存在满足 output 合同和
字节上限的结果，会抛 `WICompressError.targetUnsatisfiable`。

所有 terminal 都返回 `WIResult`，包含输出 `Data`、容器格式、
整数像素尺寸和字节数。

WICompress 不内置平台分享 preset。分享 SDK 的限制和推荐值会变化，业务代码应
根据当前接入的平台文档和产品需求，自行定义 `WICompressionTarget`。

## 错误处理

public API 使用 `throws`：

```swift
do {
    let result = try WICompressor.process(data)
} catch let error as WICompressError {
    print(error)
}
```

常见错误：

- `invalidImageData`
- `imageInfoUnavailable`
- `unsupportedSourceFormat`
- `unsupportedDestinationFormat`
- `transparentSourceRequiresBackground`
- `unsupportedColorSpace`
- `invalidICCProfile`
- `colorConversionFailed`
- `nonOpaqueJPEGBackground`
- `animatedSourceUnsupported`
- `invalidTarget`
- `targetUnsatisfiable`
- `resourceLimitExceeded`
- `thumbnailCreationFailed`
- `imageDecodeFailed`
- `destinationCreationFailed`
- `encodeFailed`

## 当前边界

WICompress 目前明确不包含：

- `UIImage` / `NSImage` convenience adapter
- Live Photo 压缩
- async API
- 只剥离 GPS 的 metadata 策略
- HDR gain map preserve
- 动图写出
- WebP / JPEG XL 写出

Live Photo 不是单张图片压缩。它至少包含 still photo resource、paired video
resource，以及二者之间的配对 metadata。首版 ImageIO core 只处理单张 still
image data，不处理 Photos 层的资源配对。

## 升级到 2.0

WICompress 2.0 使用上文的 Process 与 Target domain 替换 1.x options /
policy API。Package import 仍为 `WICompress`，静态执行入口改为
`WICompressor`。详情见 [2.0 迁移指南](docs/V2_MIGRATION_CN.md) 和
[CHANGELOG.md](CHANGELOG.md)。

## 许可证

WICompress 基于 Apache-2.0 许可证开源。详情见 `LICENSE.txt`。
