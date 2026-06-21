# WICompress v1.0.0 设计计划：ImageIO Core 重构

## 1. 背景

当前 WICompress 的核心路径绑定在 UIKit 上：

- public API 以 `UIImage` 为输入。
- resize 依赖 `UIGraphicsImageRenderer`。
- JPEG/PNG 编码依赖 `UIImage.jpegData` / `UIImage.pngData`。
- 由于 `UIImage` 不保留原始容器格式，所以 API 需要额外传入
  `formatData:`。
- 真实压缩路径只能在 iOS 环境验证，不利于通过普通 `swift test`
  覆盖核心逻辑。

我们已经确认，图片压缩核心不需要 UIKit / AppKit。只要有原始
`Data` 或文件 URL，就可以通过 ImageIO 读取容器信息、像素尺寸、
方向、metadata，并完成下采样与编码。

首版 v1.0.0 的目标是把 WICompress 从「UIKit 图片工具」重构为
「ImageIO 数据压缩核心」。

## 2. 已确认方向

1. v1.0.0 是 breaking change，不保留旧 API 兼容层。
2. 主入口只考虑 `Data` 和 `URL`。
3. 首个实现不做 `UIImage` / `NSImage` convenience adapter。
4. 首个实现不支持 Live Photo。
5. 首个实现不提供 async API。
6. public API 返回 `Data`，失败用 `throws` 表达，不返回可空。
7. public API 收敛为一套入口：`WICompress.compress(data, options:)`。
   不额外引入 `WICompressor` 链式 builder，避免出现多套配置入口。
8. 内部不做伪流水线；ImageIO 的真实中心抽象是「写入路径」。
9. `format` 和 `quality` 是两个独立 policy，不引入模糊的
   `WIEncodePolicy`。
10. `maxPixel`、target bytes、automatic format、HDR gain map 等能力先
    延后，等核心写入模型稳定后再加。
11. 实施顺序必须先保证现有 iOS simulator 行为不变，再接入 macOS
    host 测试。macOS 可测性是这次重构的目标之一，但不是替代现有 iOS
    回归测试的第一道门禁。

## 3. 核心事实：ImageIO 不是逐段 mutate 的流水线

ImageIO 的可执行操作并不是：

```text
resize -> format -> metadata -> quality -> encode
```

这些概念是用户配置语义，不是 ImageIO 内部可以逐段执行的独立步骤。

ImageIO 实际上只有两个关键融合操作：

1. load：`CGImageSourceCreateThumbnailAtIndex`
   - 解码
   - resize
   - orientation transform

2. write：`CGImageDestinationAddImage` 或
   `CGImageDestinationAddImageFromSource` + `Finalize`
   - format
   - quality
   - metadata
   - orientation tag
   - gain map / HDR 相关信息

因此内部设计不能用一个可变 `WICompressContext` 假装每个 policy 都是
独立 process。真正需要抽象的是：**本次写入应该选择哪条写入路径**。

## 4. 两条写入路径

首版编码层必须同时支持两条 ImageIO 写入路径。

### 4.1 copyFromSource：保真路径

核心调用：

```swift
CGImageDestinationAddImageFromSource(destination, source, 0, properties)
```

特点：

- 更适合保留 metadata。
- 更适合将来保留 HDR gain map。
- orientation tag 可以保留。
- resize 通过 `kCGImageDestinationImageMaxPixelSize` 表达。
- 不适合像素级重绘。
- 不适合默认 strip metadata 的上传压缩场景。

典型输出可能是：

```text
编码像素：2016x1512
方向 tag：6
展示尺寸：1512x2016
```

### 4.2 redrawBitmap：重绘路径

核心调用：

```swift
CGImageSourceCreateThumbnailAtIndex(...)
CGImageDestinationAddImage(destination, cgImage, properties)
```

特点：

- 更适合默认压缩上传。
- 更适合 strip metadata。
- 更适合格式转换。
- orientation 会被烤进像素，输出方向 tag 应该归一为 1。
- metadata / GPS / gain map 默认会丢失。

典型输出可能是：

```text
编码像素：1512x2016
方向 tag：1
展示尺寸：1512x2016
```

### 4.3 returnOriginal：短路路径

某些组合不应该重编码。例如：

```text
resize = .none
format = .preserve
metadata = .preserve
quality = .none
```

这类情况可以直接返回原始 data。

如果实现过程中仍然遇到编码结果不小于原始 data 的情况，可以在内部做
最终兜底。但这个兜底必须遵守用户声明的 policy。

核心原则：

```text
returnOriginal 只有在原始 data 满足所有当前 policy 时才允许使用。
```

例如默认 `metadata = .strip` 时，如果原图带 GPS/Exif，需要 strip 的
metadata 仍在原图里，那么不能因为重编码结果更大就返回原图。否则会违反
用户的隐私预期。

更准确地说，v1.0.0 不把 size guard 做成 public policy。已知的
「重编码后反而变大」问题应该优先通过正确的 write plan 修复：

- 不需要重编码时走 `returnOriginal`。
- 需要保真时走 `copyFromSource`。
- 默认 strip/upload 场景走 `redrawBitmap`。

实现层可以保留最终兜底，但这不是用户需要理解或配置的行为，也不能绕过
metadata / format / resize / quality 等 policy。

## 5. 内部模型

内部流程应该是：

```text
Data / URL
  -> Inspect(source)
  -> ResolveWritePlan(options, imageInfo)
  -> ExecuteWritePlan(writePlan)
  -> SizeGuard(encoded, original)
  -> Data
```

而不是：

```text
ResizeProcess
  -> FormatProcess
  -> MetadataProcess
  -> QualityProcess
  -> EncodeProcess
```

建议内部类型：

```swift
private struct WIWritePlan {
    var path: WIWritePath
    var destinationFormat: WIImageFormat
    var destinationTypeIdentifier: String
    var maxPixelSize: Int?
    var metadataPolicy: WIMetadataPolicy
    var quality: Double?
}

private enum WIWritePath {
    case returnOriginal
    case copyFromSource
    case redrawBitmap
}
```

`WIWritePlanResolver` 是核心决策点。它接收 public options 和
`WIImageInfo`，输出具体写入路径。

注意：`destinationFormat` 只表示 JPEG / PNG / HEIF 这类格式族；
真正写入 `CGImageDestination` 时必须使用 `destinationTypeIdentifier`。例如
`.preserve` 遇到 HEIC 输入时，应优先保留源图的具体 UTI，而不是只把它粗略
映射成 `.heif` 后随便选一个可写类型。

## 6. Public API 草案

首版只保留一套静态入口，适合普通调用，也适合高级配置：

使用 typed throws：错误类型已收敛为单一 `WICompressError`，包又是
swift-tools 6.0（Swift 6 工具链），因此公开抛错面统一用
`throws(WICompressError)`，调用方 `try?` / `catch` / `catch let e as
WICompressError` 写法不变。

```swift
public struct WICompress: Sendable {
    public static func compress(
        _ data: Data,
        options: WICompressOptions = .default
    ) throws(WICompressError) -> Data

    public static func compress(
        contentsOf url: URL,
        options: WICompressOptions = .default
    ) throws(WICompressError) -> Data
}
```

说明：

- 不返回 `Data?`。
- 调用方不关心错误时，可以自行使用 `try?`。
- `contentsOf:` 首版可以直接读入内存；streaming / file output 后续再做。
- `compress(data, options:)` 是完整调用，不是半截 builder。

示例：

```swift
let compressed = try WICompress.compress(data)

let preserved = try WICompress.compress(
    data,
    options: WICompressOptions(
        resize: .none,
        format: .preserve,
        metadata: .preserve,
        quality: .none
    )
)
```

## 7. 错误模型

首版提供强类型错误：

```swift
public enum WICompressError: Error, Sendable, Equatable {
    case fileReadFailed(URL)
    case invalidImageData
    case imageInfoUnavailable
    case unsupportedSourceFormat(String?)
    case unsupportedDestinationFormat(WIImageFormat)
    case animatedSourceUnsupported(frameCount: Int)
    case writePlanUnavailable
    case thumbnailCreationFailed
    case destinationCreationFailed(WIImageFormat)
    case encodeFailed(WIImageFormat)
}
```

错误语义：

- `fileReadFailed(URL)`：`compress(contentsOf:)` 读取文件失败。
- `invalidImageData`：输入 data 无法创建 `CGImageSource`。
- `imageInfoUnavailable`：无法读取像素尺寸、格式等基础信息。
- `unsupportedSourceFormat(String?)`：源格式不可识别或暂不支持。
- `unsupportedDestinationFormat(WIImageFormat)`：目标格式当前环境不可写。
- `animatedSourceUnsupported(frameCount:)`：多帧/动图暂不支持。
- `writePlanUnavailable`：options 和源图信息无法解析出合法写入路径。
- `thumbnailCreationFailed`：redraw 路径创建 downsampled `CGImage` 失败。
- `destinationCreationFailed(WIImageFormat)`：无法创建 ImageIO destination。
- `encodeFailed(WIImageFormat)`：`CGImageDestinationFinalize` 失败。

暂不把 arbitrary underlying `Error` 塞进 enum，避免 Swift 6 `Sendable`
和 `Equatable` 变复杂。后续如果确实需要更详细诊断，可以再加
`LocalizedError` 文案或 debug report API。

## 8. Public Options 草案

```swift
public struct WICompressOptions: Sendable, Equatable {
    public var resize: WIResizePolicy
    public var format: WIFormatPolicy
    public var metadata: WIMetadataPolicy
    public var quality: WIQualityPolicy

    public init(
        resize: WIResizePolicy = .luban,
        format: WIFormatPolicy = .preserve,
        metadata: WIMetadataPolicy = .strip,
        quality: WIQualityPolicy = .compression(0.6)
    )

    public static let `default` = WICompressOptions(
        resize: .luban,
        format: .preserve,
        metadata: .strip,
        quality: .compression(0.6)
    )
}
```

### 8.1 Resize Policy

```swift
public enum WIResizePolicy: Sendable, Equatable {
    case none
    case luban
}
```

首版只做：

- `.none`
- `.luban`

`maxPixel(Int)` 暂不暴露。等写入路径稳定后再加。

### 8.2 Format Policy

```swift
public enum WIFormatPolicy: Sendable, Equatable {
    case preserve
}
```

首版只做 `.preserve`。

语义：

- 源图是 JPEG，尽量输出 JPEG。
- 源图是 PNG，尽量输出 PNG。
- 源图是 HEIC/HEIF，尽量输出 HEIC/HEIF。
- 如果源格式当前环境不可写，不猜测新格式，返回原始 data 或抛出错误。

具体选择：

- 如果只是因为当前 policy 无法安全重编码，但原图本身可作为合法结果，
  可以走 `.returnOriginal`。
- 如果用户未来显式要求某个不可写目标格式，才应该抛
  `unsupportedDestinationFormat`。

`.automatic`、`.jpeg`、`.heic`、`.png` 都延后。

### 8.3 Metadata Policy

```swift
public enum WIMetadataPolicy: Sendable, Equatable {
    case strip
    case preserve
}
```

默认 `.strip`。

原因：

- 默认场景是上传压缩。
- 避免不小心保留 GPS。
- 默认走 `redrawBitmap` 路径更符合「压小」目标。

`.preserve` 会影响写入路径选择。它通常更偏向 `copyFromSource`，因为
metadata、orientation tag、未来 gain map 都与写入调用强耦合。

v1.0.0 的 `.preserve` 只承诺尽量保留普通 metadata 和 orientation tag，不
承诺保留 HDR gain map / depth / portrait matte 等 auxiliary data。Gain Map
保真需要单独的后续 policy 和测试契约，不能隐含在 metadata policy 里。

`stripLocation` 暂不做。

### 8.4 Quality Policy

```swift
public enum WIQualityPolicy: Sendable, Equatable {
    case none
    case compression(Double)
}
```

语义：

- `.none`：不设置 `kCGImageDestinationLossyCompressionQuality`。
- `.compression(Double)`：压缩质量，内部 clamp 到 `0.0...1.0`。

注意：

- `.none` 不等于无损，也不等于不重编码。
- `.none` 只表示不显式设置 ImageIO 的 lossy quality。
- 真正原样返回只能通过 `returnOriginal` 路径实现。
- quality 是否生效依赖最终目标格式。
- PNG 是无损格式，quality 对 PNG 不应被理解为有损压缩。
- 因此 quality 是 public policy，但具体是否写入 ImageIO properties 由
  `WIWritePlanResolver` / encoder 根据 destination format 决定。
- `.compression(Double)` 是编码指令，不是可从任意原始 data 反推出的硬性
  输出不变量。因此它不能单独触发 upfront `returnOriginal`；但在已经尝试
  编码后，如果输出不小于原图，且原图满足 resize / format / metadata 等
  可观察 policy，size guard 可以返回原图。

## 9. 首版默认行为

默认配置：

```swift
resize: .luban
format: .preserve
metadata: .strip
quality: .compression(0.6)
```

默认目标：

- 对大图按 Luban 策略下采样。
- 保持原始格式。
- 去掉 metadata。
- 对 JPEG/HEIC 等有损格式应用 0.6 质量。
- PNG 保持无损语义，quality 不作为有损压缩。
- 避免不必要重编码；实现层可保留「结果不小于原图则返回原图」的最终兜底。

默认通常会走 `redrawBitmap` 路径，因为 `.strip` 与 metadata/HDR 保真路径
天然冲突。

## 10. Orientation 契约

orientation 不能作为普通 metadata 简单复制。

`redrawBitmap` 路径：

- `CGImageSourceCreateThumbnailAtIndex` 应使用
  `kCGImageSourceCreateThumbnailWithTransform`。
- 方向被烤进像素。
- 输出 orientation tag 应归一为 1 或不写源 orientation。

`copyFromSource` 路径：

- orientation tag 可以保留。
- 输出编码像素尺寸不一定等于展示尺寸。

因此测试不能只断言裸编码像素。测试应该断言：

```text
displayDimensions(output) == expectedDisplayDimensions
```

即输出也要读取 orientation，再换算展示尺寸。

## 11. Format Model

`WIImageFormat` 只表示图像容器格式，不表示输出策略。

当前字符串 contains 判断应该替换为 `UTType` conformance。

首版支持：

- JPEG
- PNG
- HEIF/HEIC
- unknown / unsupported

未来再考虑：

- WebP
- JPEG XL
- GIF / animated image

是否支持某格式不能只看能不能读，还要看当前运行环境是否能写。写能力
必须通过 `CGImageDestinationCopyTypeIdentifiers()` 运行时判断。

## 12. WIImageInfo

`WIWritePlanResolver` 依赖 `WIImageInfo` 做决策。首版至少需要以下字段：

```swift
struct WIImageInfo {
    let sourceFormat: WIImageFormat
    let typeIdentifier: String?
    let pixelWidth: Int
    let pixelHeight: Int
    let orientation: Int
    let frameCount: Int
    let isSourceFormatWritable: Bool
    let hasMetadata: Bool
    let hasGPS: Bool
    let hasGainMap: Bool
    let hasAlpha: Bool?
}
```

说明：

- `frameCount > 1` 首版直接抛 `animatedSourceUnsupported`。
- `hasGPS` / `hasMetadata` 会影响 `.metadata(.strip)` 下是否允许
  `returnOriginal`。
- `hasMetadata` 指会被 `.strip` 移除的可剥离 metadata，例如 Exif / GPS /
  TIFF / maker notes 等；不应把 ICC profile / color space、像素尺寸、
  必要的 orientation 处理混在里面。色彩 profile 属于显示语义，不是隐私
  metadata。
- `.preserve` 格式策略需要保留 `typeIdentifier`，不能只保留粗粒度
  `WIImageFormat`。
- `hasGainMap` 首版不做 preserve，但需要识别出来，避免未来架构重写。
- `hasAlpha` 首版不参与默认 `.preserve`，但为后续 PNG -> JPEG /
  automatic format 留入口。

## 13. WIWritePlanResolver 规则表

resolver 是 v1.0.0 的核心 spec。public policy 只是用户语义，真正执行
必须落到 write plan。

基础原则：

```text
returnOriginal 只有在原始 data 满足所有当前 policy 时才允许使用。
```

实际实现应按以下优先级解析，而不是把下表当成互斥的 if/else 随机排列：

```text
ValidateSource
  -> ResolveDestinationTypeIdentifierAndWritability
  -> CheckUpfrontReturnOriginal
  -> ChooseWritePath
  -> ExecuteWritePath
  -> ApplySizeGuardIfAllowed
```

`originalSatisfiesPolicies` 的首版语义：

- `format == .preserve`：原始 data 的具体 `typeIdentifier` 就是目标类型。
- `metadata == .preserve`：原始 metadata 本身满足要求。
- `metadata == .strip`：原始 data 不包含需要剥离的 metadata，才允许返回原图。
- `resize == .none`：原始展示尺寸满足要求。
- `resize == .luban`：只有 Luban ratio 为 1，或者原始展示尺寸已经等于目标
  展示尺寸时，才允许返回原图。
- `quality == .none`：原始 data 满足“不显式设置 lossy quality”的要求。
- `quality == .compression`：不能用于 upfront `returnOriginal`；只能在已经
  编码且输出不小于原图时，配合其它可观察 policy 通过 size guard 返回原图。

首版规则：

| 条件 | 写入路径 | 说明 |
| --- | --- | --- |
| 无法创建 `CGImageSource` | throw `invalidImageData` | 输入不是可识别图片 |
| 无法读取基础信息 | throw `imageInfoUnavailable` | 缺少像素尺寸/格式等 |
| `frameCount > 1` | throw `animatedSourceUnsupported` | 首版不拍平成第 0 帧 |
| 源格式 unknown/unsupported | throw `unsupportedSourceFormat` | 不猜测输出格式 |
| `resize == .none && format == .preserve && metadata == .preserve && quality == .none` | `returnOriginal` | 真正原样返回 |
| `metadata == .preserve` | `copyFromSource` | 保留 metadata/orientation，未来也适合 gain map |
| `metadata == .strip` | `redrawBitmap` | 默认上传压缩路径，orientation bake into pixels |
| `format == .preserve && sourceFormat not writable && original satisfies policies` | `returnOriginal` | 原图本身是合法结果时可短路 |
| `format == .preserve && sourceFormat not writable && original does not satisfy policies` | throw `unsupportedDestinationFormat` | 不能违反 strip 等 policy |
| 编码结果不小于原图，且原图满足所有 policy | `returnOriginal` | 内部兜底 |
| 编码结果不小于原图，但原图不满足所有 policy | 返回编码结果或 throw | 不能因 size 兜底泄漏 metadata |

特别注意：

- 默认 `.metadata(.strip)` 下，不能因为压缩结果更大就返回带 GPS/Exif 的
  原图。
- `.quality(.none)` 不是 returnOriginal 条件的一部分；只有完整命中
  `resize.none + format.preserve + metadata.preserve + quality.none` 才是
  原样返回。

## 14. 文件布局建议

仍保持单 target。

建议布局：

```text
Sources/WICompress/
  Core/
    WICompress.swift
    WICompressOptions.swift
    WICompressError.swift
    WIImageFormat.swift
    WIImageInfo.swift
    WIImageSource.swift
    WIWritePlan.swift
    WIWritePlanResolver.swift
    WIImageEncoder.swift
    WIImageUtils.swift
```

首版不需要：

```text
Sources/WICompress/iOS/
Sources/WICompress/macOS/
```

## 15. 线程模型

首版只提供同步 API。

原因：

- 压缩是 CPU / I/O 工作。
- queue、priority、cancellation、memory pressure 更适合由业务层决定。
- 同步 core 更容易测试。

调用方需要异步时可以自己包：

```swift
let compressed = await Task.detached(priority: .utility) {
    try WICompress.compress(data)
}.value
```

未来如果需要 async API，也应该只是同步 core 的薄封装。

## 16. 首版明确不做

- UIKit `UIImage` adapter
- AppKit `NSImage` adapter
- Live Photo
- async API
- public result/report object
- `WICompressor` 链式 builder
- `.automatic` format policy
- 显式 `.jpeg` / `.png` / `.heic` format policy
- PNG -> JPEG 的 background/alpha 配置
- `maxPixel`
- public size guard policy
- `maxFileSize` / target bytes 二分压缩
- HDR gain map preserve
- `stripLocation`
- animated image
- WebP / JPEG XL 写出

## 17. 后续扩展方向

### 17.1 FormatPolicy 扩展

未来可以增加：

```swift
case automatic
case jpeg(background: WIJPEGBackground = .disallow)
case png
case heic
```

但需要先定义清楚：

- alpha 怎么处理
- HEIC 写出不可用怎么处理
- PNG 是否允许自动转 JPEG
- 用户显式要求格式失败时是 throw 还是 fallback

#### PNG -> JPEG / alpha background

确实存在「上传端统一只收 JPEG」的需求，但这不是 v1.0.0 的默认心智。
PNG -> JPEG 技术上可以通过 ImageIO/CoreGraphics 完成，但它必然改变像素
语义：

- JPEG 不支持 alpha。
- 透明区域需要合成到某个背景上。
- 任意颜色都必须回答色彩空间问题：这个红色是 sRGB 的红，还是 P3 的红。
- 白色 `(1, 1, 1)` 和黑色 `(0, 0, 0)` 在 RGB 色彩空间里没有歧义，是
  可以先支持的安全子集。
- 自定义颜色需要和色彩空间一起设计，延后。

未来如果支持 JPEG 转换，应通过明确 options 表达，而不是提供无配置
`toJPEG(data)`。示意：

```swift
public enum WIJPEGBackground: Sendable, Equatable {
    case disallow
    case white
    case black
    // future: case custom(WIColor)
}

let output = try WICompress.compress(
    data,
    options: WICompressOptions(
        format: .jpeg(background: .white)
    )
)
```

默认 `.jpeg(background: .disallow)` 是安全行为：如果源图带 alpha，就抛
明确错误，绝不偷偷铺白。未来可增加错误：

```swift
case transparentSourceRequiresBackground(WIImageFormat)
```

格式转换还会影响 size guard：当用户明确要求 JPEG 时，不能因为输出更大就
偷偷返回原始 PNG/HEIC，否则上传端仍然不接受。这个联动等显式格式转换进入
设计时再处理。

未来 resolver 规则：

- `format != .preserve` 时禁用 `returnOriginal` / size 兜底，除非原图本身
  已满足目标格式。
- `format == .jpeg(background: ...)` 必须走 `redrawBitmap`。
- 源图带 alpha 且 background 为 `.disallow` 时抛
  `transparentSourceRequiresBackground`。
- 源图带 alpha 且 background 为 `.white` / `.black` 时，在 redraw 路径中
  增加 flatten 子步骤：创建 opaque CGContext，填充背景色，再绘制下采样图，
  最后写 JPEG。
- flatten 使用源图色彩空间；白/黑在 RGB 空间无歧义。

### 17.2 QualityPolicy 扩展

未来可以增加：

```swift
case targetBytes(Int, range: ClosedRange<Double>)
```

它应该属于 quality policy，而不是全局 size policy。

### 17.3 ResizePolicy 扩展

未来可以增加：

```swift
case maxPixel(Int)
```

两条写入路径都能支持：

- `redrawBitmap`：传给 thumbnail max pixel size。
- `copyFromSource`：传给 `kCGImageDestinationImageMaxPixelSize`。

### 17.4 MetadataPolicy 扩展

未来可以增加：

```swift
case stripLocation
```

但要谨慎处理 orientation、Exif、GPS、maker notes、gain map 等耦合关系。

### 17.5 Live Photo

Live Photo 不是普通 image compression。它至少包括：

- still photo resource
- paired video resource
- 两者之间的 metadata pairing

未来如果做，应在 Photos 相关层设计，不进入首版 ImageIO core。

## 18. 实施验证策略

这次重构的验证顺序不是直接用 macOS `swift test` 替代现有 iOS 行为验证。
正确顺序是：

```text
iOS simulator 旧 API characterization baseline
  -> 新 Data/ImageIO core 与同一组 fixture 对齐
  -> iOS simulator 新 API 行为通过
  -> macOS host `swift test` 覆盖 UIKit-free core
```

实施期间必须保留一个短暂的双轨阶段：

- 旧 `UIImage` API 先保留，用来跑现有 iOS simulator baseline。
- 新 `Data` API 先并行落地，测试同一组 fixture 的格式、展示尺寸、metadata
  行为和大小兜底。
- 只有新旧行为在 iOS simulator 上确认符合 v1.0.0 contract 后，才删除旧
  `UIImage` API。
- macOS host 测试应在核心不再依赖 UIKit 后接入，用来提升日常测试效率，
  不是用来证明旧 iOS 行为没有回归。

建议门禁：

```bash
xcodebuild test -scheme WICompress -destination 'platform=iOS Simulator,name=<available simulator>'
swift test
```

其中 `xcodebuild test` 是 cut-over 前后的行为回归门禁，`swift test` 是
ImageIO core 完成 UIKit-free 后的快速核心门禁。

## 19. TODO

### Phase 0 - iOS Safety Net（已完成，实施前必须重跑）

- [x] `CharacterizationTests` 自动发现 `Resources/` 下的图片。
- [x] `Package.swift` 使用 `.copy` 保存 fixture 原始字节。
- [x] 加入真实 HEIC/JPEG/PNG fixture。
- [x] 覆盖 orientation 1 和 6。
- [x] 记录当前 baseline。
- [x] 实施 Phase 1 前，在 iOS simulator 上跑通现有 characterization /
      compression 测试，确认旧 API baseline 可用。

### Phase 1 - Public Surface（已完成）

- [x] 新增 `WICompressError`。
- [x] 新增 `WICompressOptions`。
- [x] 新增 `WIResizePolicy`。
- [x] 新增 `WIFormatPolicy`。
- [x] 新增 `WIMetadataPolicy`。
- [x] 新增 `WIQualityPolicy`。
- [x] 新增 `WICompress.compress(_ data:options:) throws -> Data`，其中
      `options` 默认 `.default`。
- [x] 新增 `WICompress.compress(contentsOf:options:) throws -> Data`，其中
      `options` 默认 `.default`。
- [x] 旧 `UIImage` API 暂时保留，直到新 Data API 在 iOS simulator 上通过
      同一组 fixture contract。

### Phase 2 - ImageIO Core（已完成）

- [x] 新增 `WIImageInfo`。
- [x] 新增 `WIImageSource`。
- [x] 新增 `WIWritePlan`。
- [x] 新增 `WIWritePlanResolver`。
- [x] 落地 resolver 规则表。
- [x] 新增 `WIImageEncoder`。
- [x] 支持 `returnOriginal`。
- [x] 支持 `copyFromSource`。
- [x] 支持 `redrawBitmap`。
- [x] 修复不必要重编码导致输出变大的问题；内部兜底不得违反 policy。
- [x] 为新 Data API 建立 SwiftPM characterization，对齐 Phase 0 的 fixture
      contract。
- [x] 在 iOS simulator 上复跑 Data API characterization。

### Phase 3 - Cut Over（已完成）

- [x] CharacterizationTests 改为走 Data API。
- [x] 在 iOS simulator 上确认 Data API 通过真实 fixture contract。
- [x] 删除 `WIImageCompressor`。
- [x] 删除旧 `resizeImage(_:)` API。
- [x] 删除旧 `compressImage(_:quality:formatData:)` API。
- [x] 将核心文件移动到 `Core/`。

### Phase 4 - macOS Host Coverage（已完成）

- [x] 移除不再需要 UIKit 的测试条件编译。
- [x] `swift test` 在 macOS host 上覆盖 Data/ImageIO core。
- [x] 保留 iOS simulator 测试作为平台行为回归门禁。

### Phase 5 - Test Matrix（已完成）

- [x] JPEG / PNG / HEIC preserve format。
- [x] `.metadata(.strip)` 走 redraw 行为。
- [x] `.metadata(.preserve)` 走 copyFromSource 行为。
- [x] `.quality(.none)` 不设置 lossy quality。
- [x] `.quality(.compression)` 对 JPEG/HEIC 生效。
- [x] PNG 不被 quality 误解为有损压缩。
- [x] P3 / color profile 在 `copyFromSource` 和 `redrawBitmap` 两条路径下都
      不应被意外降级为 sRGB；断言显示语义，不要求 ICC 原始字节完全一致。
- [x] PNG alpha 在 `redrawBitmap` 后必须保留，不得隐式铺白、铺黑或创建
      opaque context 导致透明通道丢失。
- [x] 输出展示尺寸符合 Luban 预期；HEIC 等编码器可能做偶数像素对齐，测试
      允许 1px 以内误差。
- [x] 输出裸编码尺寸允许因 orientation tag 不同而不同。
- [x] corrupt / truncated / empty input 抛出明确错误。
- [x] 多帧/动图输入抛出 `animatedSourceUnsupported`。
- [x] 不可写目标格式行为明确。
- [x] `.metadata(.strip)` 下不能因 size 兜底返回带 GPS/Exif 的原图。
- [x] `.metadata(.strip)` 下不能因 size 兜底绕过 orientation 归一化。
- [x] 记录 v1 `.metadata(.preserve)` 不承诺保留 HDR gain map 的当前行为。

### Phase 6 - Release

- [x] 更新 README。
- [x] 更新 README_CN。
- [x] 写迁移说明。
- [x] 生成 README 压缩效果对比图。
- [x] 说明首版不包含 UIKit/AppKit adapter。
- [x] 说明首版不支持 Live Photo。
- [x] 运行 `swift test`。
- [ ] tag `v1.0.0`。

## 20. 验证标准

首版默认 API：

```swift
let compressed = try WICompress.compress(data)
```

高级配置：

```swift
let compressed = try WICompress.compress(
    data,
    options: WICompressOptions(metadata: .preserve, quality: .none)
)
```

应该满足：

- 实施期间先通过 iOS simulator 回归测试，确认真实 fixture 的既有可观察
  行为没有意外漂移。
- 对普通图片能稳定输出 data。
- 对无法识别输入抛明确错误。
- 默认不会因为不必要重编码产生比原图更大的结果。
- `returnOriginal` 不会违反调用方声明的 metadata/format/quality/resize policy。
- 默认不依赖 UIKit / AppKit。
- ImageIO core 完成后，macOS 下普通 `swift test` 可以覆盖核心逻辑。
- CharacterizationTests 断言展示尺寸，而不是只断言裸编码像素。
