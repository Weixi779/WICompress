# WICompress

![Platform](https://img.shields.io/badge/platform-iOS%2014.0%2B%20%7C%20macOS%2011.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange)
![SPM Support](https://img.shields.io/badge/SPM-Supported-brightgreen)
![License](https://img.shields.io/github/license/Weixi779/WICompress)

[English](README.md) | 简体中文

用一组简单、可预测的 Swift API 完成上传前图片压缩。

`WICompress` 是一个基于 ImageIO 的 Swift 图片压缩库，直接处理原始图片
`Data` 或文件 `URL`。底层由 ImageIO 负责格式识别、方向、alpha、metadata、
色彩 profile、缩放和编码；public API 保持简单，最终返回压缩后的 `Data`。

默认保留 JPEG / PNG / HEIC 源格式，也可以在上传端要求固定容器时显式转成
JPEG、PNG 或 HEIC，或者按 alpha 通道自动选择 PNG / JPEG；默认剥离隐私
metadata，并且不依赖 `UIImage` / `NSImage`。

```swift
let compressedData = try WICompress.compress(originalData)
```

```swift
let uploadData = try WICompress.compress(
    originalData,
    options: WICompressOptions(
        resize: .maxPixel(1600),
        format: .jpeg(background: .white),
        metadata: .strip,
        quality: .compression(0.7)
    )
)
```

## 为什么用 WICompress

- **Data in, Data out**：保留相册、文件或网络拿到的原始字节，直接传给压缩器。
- **适合上传的默认值**：Luban resize、metadata strip、JPEG/HEIC 有损质量。
- **Resize 策略灵活**：支持 Luban、最长边限制，以及按最小/最大展示尺寸区间 fit。
- **格式可控**：默认保持源格式，也可以显式输出 JPEG、PNG、HEIC，或按 alpha
  通道有无选择 PNG / JPEG。
- **透明图转 JPEG 更安全**：必须显式选择白底或黑底，不会偷偷铺底。
- **方向安全**：基于 ImageIO 读取展示尺寸，redraw path 会把方向烘焙进像素。
- **核心不依赖 UIKit / AppKit**：可在 iOS App、macOS 工具和 SwiftPM 测试中使用。
- **强类型错误**：失败通过 `WICompressError` 表达，不再返回可空 `Data?`。

## 压缩效果预览

下面这张对比图由 `scripts/generate-doc-assets.swift` 基于仓库内的真图
fixtures 生成。后续压缩行为变化时，可以重新生成这张图。

```bash
swift run WICompressDocAssetGenerator
```

![WICompress 压缩效果对比](docs/assets/compression-comparison.png)

图里每一行都使用默认 API。前三行优先展示 HEIC，因为这是最值得被用户看到的
真实场景；后面再展示 JPEG 和 PNG。PNG 不是被跳过：长截图触发 Luban resize
后会变小，而 alpha PNG 这一行只是 no-op case，原图本身已经是更好的结果。

## 示例项目

仓库包含 SwiftUI 示例项目：

1. 打开 `Example/WICompressExample/WICompressExample.xcodeproj`。
2. 在 iOS 设备或模拟器上运行。
3. 从相册选择图片，比较原始 data 和压缩后 data。

示例覆盖：

- `PhotosPicker` 和 `PHPickerViewController` 获取原始图片 `Data`
- `WICompress.compress(_:)` 压缩
- 格式检测
- 原图 / 压缩图预览
- 文件大小和压缩比展示

## API 示例

```swift
import WICompress

let compressedData = try WICompress.compress(originalData)
```

压缩文件 URL：

```swift
let compressedData = try WICompress.compress(contentsOf: imageURL)
```

显式配置：

```swift
let compressedData = try WICompress.compress(
    originalData,
    options: WICompressOptions(
        resize: .luban,
        format: .preserve,
        metadata: .strip,
        quality: .compression(0.7)
    )
)
```

把图片资产 fit 到调用方定义的展示尺寸区间：

```swift
let assetData = try WICompress.compress(
    originalData,
    options: WICompressOptions(
        resize: .fit(
            minSize: WISize(width: 40, height: 50),
            maxSize: WISize(width: 400, height: 467)
        ),
        format: .pngIfAlphaOtherwiseJPEG,
        metadata: .strip,
        quality: .compression(0.7)
    )
)
```

## 和 UIKit / AppKit 一起使用

`WICompress` 不接收 `UIImage` 或 `NSImage`。业务层应该保留从相册、文件、
网络或数据库拿到的原始图片 `Data`，把这份 `Data` 传给 `WICompress`。如果
UI 需要预览，再在边界处把压缩结果解码成 `UIImage` / `NSImage`。

```swift
guard let originalData = try await photosPickerItem.loadTransferable(type: Data.self) else {
    throw MyError.missingImageData
}

let compressedData = try WICompress.compress(originalData)
let previewImage = UIImage(data: compressedData)
```

这样调用方不需要同时传入「渲染后的图片」和「原始格式数据」。ImageIO 可以
直接从原始字节读取格式、尺寸、方向和 metadata。

## Options

默认配置面向普通上传压缩：

```swift
WICompressOptions(
    resize: .luban,
    format: .preserve,
    metadata: .strip,
    quality: .compression(0.6)
)
```

### Resize

```swift
public struct WISize {
    public var width: Double
    public var height: Double
}

public enum WIResizePolicy {
    case none
    case luban
    case maxPixel(Int)
    case fit(minSize: WISize, maxSize: WISize)
}
```

- `.luban`：默认值。按 Luban 策略对大图等比下采样。
- `.maxPixel(value)`：把最长展示边限制到 `value` 像素，不会放大小图。
- `.fit(minSize:maxSize:)`：保持比例；只有宽高都小于 `minSize` 时才放大；
  只要任意一边超过 `maxSize` 就缩小，确保输出整体落进 `maxSize`；已经在
  `maxSize` 内且不满足小图放大条件时不额外缩放。这个策略可以放大小图 bitmap，
  同时核心仍不依赖 UIKit / AppKit。
- `.none`：保留源图展示尺寸。

### Format

```swift
public enum WIJPEGBackground {
    case disallow
    case white
    case black
}

public enum WIFormatPolicy {
    case preserve
    case jpeg(background: WIJPEGBackground = .disallow)
    case pngIfAlphaOtherwiseJPEG
    case png
    case heic
}
```

- `.preserve`：默认值。保持源图容器格式。
- `.jpeg(background:)`：输出 JPEG。透明源图需要显式选择 `.white` 或
  `.black` 背景；`.disallow` 会抛错，避免偷偷铺底。
- `.pngIfAlphaOtherwiseJPEG`：源图有 alpha 通道时输出 PNG，否则输出 JPEG。
- `.png`：输出 PNG。PNG 是无损格式，quality 策略会被忽略。
- `.heic`：在当前平台支持 HEIC 写出时输出 HEIC。

显式格式转换和按 alpha 自动选择格式都会重写图片。调用方指定了非 preserve 的
目标格式策略时，size guard 不会再返回原始字节。

### Metadata

```swift
public enum WIMetadataPolicy {
    case strip
    case preserve
}
```

- `.strip`：默认值。重写图片时剥离 Exif / GPS / TIFF / maker notes 等可剥离 metadata。
- `.preserve`：尽量保留普通 metadata 和 orientation tag，内部会优先走 source-copy 写入路径。

如果格式转换强制走 redraw path，`.preserve` 会尽量重新附加普通 metadata
字典。方向信息仍会被烘焙进像素并重置为 `1`，否则读取方会对已经旋转过的像素
再次旋转。

色彩 profile 不是 Exif/GPS 这类隐私 metadata，而是显示语义的一部分。
Display P3 profile 在 `copyFromSource` 和 `redrawBitmap` 两条路径下都应该保留。

初始公开版不承诺保留 HDR gain map。Gain map 是辅助图像数据，不是普通
Exif/GPS 字典，后续需要单独的 policy 和测试契约。

### Quality

```swift
public enum WIQualityPolicy {
    case none
    case compression(Double)
}
```

- `.compression(value)`：内部 clamp 到 `0.0...1.0`，只对 JPEG / HEIC 这类有损格式生效。
- `.none`：不设置 `kCGImageDestinationLossyCompressionQuality`。

`.none` 不等于无损，也不等于一定原样返回。真正原样返回只会在当前 options
允许且原始 data 已满足所有可观察 policy 时发生。

PNG 是无损格式，quality 对 PNG 不会被理解为有损压缩。

## 错误处理

public API 使用 `throws`：

```swift
do {
    let compressedData = try WICompress.compress(data)
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
- `animatedSourceUnsupported`
- `thumbnailCreationFailed`
- `destinationCreationFailed`
- `encodeFailed`

## 当前边界

WICompress 目前明确不包含：

- `UIImage` / `NSImage` convenience adapter
- Live Photo 压缩
- async API
- 只剥离 GPS 的 metadata 策略
- target bytes / max file size 压缩
- HDR gain map preserve
- 动图写出
- WebP / JPEG XL 写出

Live Photo 不是单张图片压缩。它至少包含 still photo resource、paired video
resource，以及二者之间的配对 metadata。首版 ImageIO core 只处理单张 still
image data，不处理 Photos 层的资源配对。

## 从 0.x 升级

WICompress 1.0.0 用上文展示的 `Data` / `URL` 核心 API 替换旧的
`UIImage` API。破坏性变更摘要见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

WICompress 基于 Apache-2.0 许可证开源。详情见 `LICENSE.txt`。
