# WICompress

![Platform](https://img.shields.io/badge/platform-iOS%2014.0%2B%20%7C%20macOS%2011.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange)
![SPM Support](https://img.shields.io/badge/SPM-Supported-brightgreen)
![License](https://img.shields.io/github/license/Weixi779/WICompress)

[English](README.md) | 简体中文

`WICompress` 是一个基于 ImageIO 的轻量级图片压缩库，支持 JPEG、PNG、
HEIC/HEIF 数据压缩。v1.0.0 的核心入口不再依赖 UIKit / AppKit，而是直接
处理原始 `Data` 或文件 `URL`。

## 特性

- Data-first API：输入原始 `Data` 或文件 `URL`，输出压缩后的 `Data`。
- 核心不依赖 UIKit / AppKit：可在 iOS App 中使用，也可在 macOS 上跑 SwiftPM 测试。
- 保持源格式：JPEG 仍输出 JPEG，PNG 仍输出 PNG，HEIC/HEIF 仍输出 HEIC/HEIF。
- Luban 尺寸策略：对大图按 Luban 比例下采样，断言展示尺寸而不是裸编码像素。
- Metadata 策略：默认剥离 Exif/GPS 这类上传场景不需要的信息，也可以显式保留。
- 强类型错误：失败通过 `WICompressError` 表达，不再返回可空 `Data?`。

## 系统要求

- iOS 14.0+
- macOS 11.0+
- Swift 6.0+

## 安装

### Swift Package Manager

1. 在 Xcode 中打开你的项目。
2. 选择 **File** -> **Add Packages**。
3. 输入仓库地址：`https://github.com/Weixi779/WICompress`。
4. 选择版本并添加 `WICompress` product。

## 快速开始

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
public enum WIResizePolicy {
    case none
    case luban
}
```

- `.luban`：默认值。按 Luban 策略对大图等比下采样。
- `.none`：保留源图展示尺寸。

### Format

```swift
public enum WIFormatPolicy {
    case preserve
}
```

v1.0.0 只支持 `.preserve`。显式格式转换，例如 PNG -> JPEG，暂不进入首版。
原因是 JPEG 不支持 alpha，PNG 转 JPEG 必须要求调用方明确选择背景色，而不
应该偷偷铺白。

### Metadata

```swift
public enum WIMetadataPolicy {
    case strip
    case preserve
}
```

- `.strip`：默认值。重写图片时剥离 Exif / GPS / TIFF / maker notes 等可剥离 metadata。
- `.preserve`：尽量保留普通 metadata 和 orientation tag，内部会优先走 source-copy 写入路径。

色彩 profile 不是 Exif/GPS 这类隐私 metadata，而是显示语义的一部分。
Display P3 profile 在 `copyFromSource` 和 `redrawBitmap` 两条路径下都应该保留。

v1.0.0 不承诺保留 HDR gain map。Gain map 是辅助图像数据，不是普通 Exif/GPS
字典，后续需要单独的 policy 和测试契约。

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
- `animatedSourceUnsupported`
- `thumbnailCreationFailed`
- `destinationCreationFailed`
- `encodeFailed`

## 当前边界

v1.0.0 明确不包含：

- `UIImage` / `NSImage` convenience adapter
- Live Photo 压缩
- async API
- 显式 `.jpeg` / `.png` / `.heic` 格式转换策略
- PNG -> JPEG 的 alpha 背景色合成
- target bytes / max file size 压缩
- HDR gain map preserve
- 动图写出
- WebP / JPEG XL 写出

Live Photo 不是单张图片压缩。它至少包含 still photo resource、paired video
resource，以及二者之间的配对 metadata。首版 ImageIO core 只处理单张 still
image data，不处理 Photos 层的资源配对。

## 从 0.x 迁移

v1.0.0 是 breaking change，旧 `UIImage` API 已删除：

```swift
WICompress.resizeImage(_:)
WICompress.compressImage(_:quality:formatData:)
```

改为传入原始图片字节：

```swift
let compressedData = try WICompress.compress(
    originalData,
    options: WICompressOptions(quality: .compression(0.7))
)
```

详细迁移说明见 [docs/MIGRATION_v1.0.0.md](docs/MIGRATION_v1.0.0.md)。

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

## 测试

核心使用 Swift Testing 覆盖，并同时跑 macOS host 与 iOS simulator：

```bash
swift test
xcodebuild test \
  -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme WICompress \
  -destination 'platform=iOS Simulator,name=<device>' \
  CODE_SIGNING_ALLOWED=NO
```

## 许可证

WICompress 基于 MIT 许可证开源。详情见 `LICENSE`。
