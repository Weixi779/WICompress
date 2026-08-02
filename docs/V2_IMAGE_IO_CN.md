# WIImageIO 2.0

状态：同步 public product、typed chain、Data/file reader、静态图片 decode、thumbnail、
source transcode、pixel encode、metadata 与 runtime capability 已实现。异步调度仍属于
`WICompressor` terminal，不进入 ImageIO。

相关边界：

- [`V2_IMAGE_DOMAIN_CN.md`](V2_IMAGE_DOMAIN_CN.md)：共享图片事实与压缩请求领域。
- [`V2_IMAGE_RENDERING_CN.md`](V2_IMAGE_RENDERING_CN.md)：orientation、crop、resize 与颜色渲染。
- [`V2_IMAGE_PIPELINE_CN.md`](V2_IMAGE_PIPELINE_CN.md)：Process/Target 的请求级编排。

## 目标

`WIImageIO` 解决 ImageIO 自身的机械复杂度：

- `CGImageSource` 的生命周期与 Data/file 双入口。
- decode 前 inspection。
- thumbnail 与 orientation transform。
- `CGImageDestination` create/add/finalize。
- metadata dictionary 的选择与 source provenance。
- runtime decode/encode capability。

它不解释 Process、Target、crop、resize、Alpha flatten、颜色转换或 byte-budget 搜索。
这些仍由 `ImagePipeline` 与 Rendering 拥有。

## Product 与依赖

Package 提供两个 library product：

```swift
.product(name: "WICompress", package: "WICompress")
.product(name: "WIImageIO", package: "WICompress")
```

只需要底层 ImageIO 能力时：

```swift
import WIImageIO
```

依赖方向：

```text
                    WIImageDomain
                  ↑       ↑       ↑
         WIImageIO  WIImageRendering  WICompressDomain
                  ↖      ↑      ↗
                WICompressExecution
                         ↑
                     WICompress
```

`WIImageDomain` 保存两条产品线共同使用的事实。`WIImageIO` 直接 re-export
`WIPixelSize`、`ImageFormat`、`WIImageOrientation`、`ImageMetadataOptions` 与
`WIColorSpace`；使用者无需另外 import 基础 target，也不创建第二套 scoped aliases。

## Public API

典型像素链：

```swift
let data = try ImageReader(sourceData)
    .thumbnail(
        options: .init(maximumPixelSize: 1_280)
    )
    .encode(
        as: .jpeg,
        options: .init(
            compressionQuality: 0.72,
            metadata: .strip
        )
    )
```

File URL 不会预先 materialize 完整 Data：

```swift
let reader = try ImageReader(contentsOf: fileURL)
let descriptor = reader.descriptor
```

无需 decode pixels 的 source transcode：

```swift
let data = try reader.transcode(
    as: .jpeg,
    options: .init(metadata: .preserve)
)
```

公共入口保持很窄：

```text
ImageReader(Data) / ImageReader(contentsOf: URL) -> ImageReader
ImageReader.descriptor                           -> ImageDescriptor
ImageReader.image(options:)                     -> ImageFrame
ImageReader.thumbnail(options:)                 -> ImageFrame
ImageReader.transcode(as:options:)              -> Data
ImageFrame.encode(as:options:)                  -> Data
ImageReader.inspect(...)                        -> ImageDescriptor
ImageReader.canDecode / ImageReader.canEncode   -> Bool
```

这里的链不是通用 Builder。每个节点都拥有真实状态或不变量，不允许任意 Stage、插件、
Registry 或跨请求 mutable session。

公共类型刻意采用扁平命名，不再添加人工 namespace。若同时导入其他也声明 `ImageReader`
的模块，调用方使用 `WIImageIO.ImageReader` 消除歧义；这是 2.0 接受的模块命名成本。

## ImageReader

`ImageReader` 是同步、只读、请求级 ImageIO source：

- 持有一个未公开的 `CGImageSource`。
- 初始化时只 inspect 一次并缓存 `ImageDescriptor`。
- Data reader 只保留 ImageIO source 所需的输入生命周期。
- File reader 直接从 URL 创建 source，不负责产品层的原始字节 passthrough。
- 不声明 `Sendable`；调用方不应跨并发域共享同一个 ImageReader。

`ImageReader` 不是 Pipeline、Domain container 或业务扩展点。纯尺寸算法、Rendering 与候选搜索
只接收自己需要的值，不接收 ImageReader。原始 `Data` / file URL 与 return-original 生命周期
由产品 Pipeline 持有，不进入 ImageReader。

## ImageDescriptor

`ImageDescriptor` 是 `Sendable` 的 source facts：

| Fact | 含义 |
| --- | --- |
| `type` / `format` | ImageIO type 与稳定容器家族 |
| `byteCount` | encoded Data 或 file size |
| `pixelSize` | stored pixel width/height |
| `orientation` | encoded display orientation |
| `orientedPixelSize` | 应用 orientation 后的显示像素尺寸 |
| `frameCount` | source frame 数量 |
| `hasAlpha` | ImageIO 可确认时的 Alpha 事实 |
| `metadata` | 已建模 metadata 类别 |
| `hasUnmodeledMetadata`（package-only） | 是否存在不能安全选择的 metadata |
| `hasGainMap` | 是否存在 HDR gain map auxiliary data |

颜色空间仍按需通过 `ImageReader.colorSpace()` 读取，不在 inspection 时强制完整 decode。

## ImageFrame 与 orientation

裸 `CGImage` 不能表达 pixels 是否已经按 EXIF orientation 转正，也不能表达 metadata
来自哪里。`ImageFrame` 因此同时持有：

```text
CGImage + orientation + optional source metadata provenance
```

状态合同：

| 产生方式 | ImageFrame orientation | Encode 行为 |
| --- | --- | --- |
| `ImageReader.image()` | source orientation | 写回原 orientation |
| `ImageReader.thumbnail()` 默认 transform | `.up` | 写入 orientation 1 |
| `thumbnail(appliesOrientationTransform: false)` | source orientation | 保留 source orientation |
| `ImageFrame(image:)` | 默认 `.up` | 不伪造 source metadata |
| Pipeline Rendering 输出 | `.up` | 保留被选择的 source metadata，方向写 1 |

这避免两类常见错误：raw pixels 被错误标记为 `.up`，或已经转正的 thumbnail/rendered
pixels 又被旧 orientation 旋转一次。

## Metadata provenance

ImageReader 产生的 ImageFrame 保留 source provenance。`ImageFrame.encode` 根据 `ImageEncodeOptions.metadata`
从创建 ImageFrame 时截取的 metadata snapshot 中选择字段。ImageFrame 不强引用 ImageReader、原始
Data 或 `CGImageSource`；调用方自己创建的 `ImageFrame(image:)` 没有 source provenance，
因此 `.preserve` 不会凭空产生 metadata。

当前建模类别：

- Exif / Exif auxiliary。
- GPS。
- IPTC。
- TIFF（排除 display orientation）。
- MakerNote（包括 Exif dictionary 内嵌 MakerNote）。

未建模 metadata 不会被误判为可选择子集。GPS-only transcode 可以使用 ImageIO 底层的
source-copy 机制，不需要 decode pixels。HDR gain map 当前只 inspect，不承诺在重新编码后
保留。

## Decode、Transcode 与 Encode

三条 primitive 路径不可混成一个含糊操作：

```text
ImageReader -> image / thumbnail -> ImageFrame -> encode -> Data
ImageReader -> transcode                           -> Data
ImageReader -> descriptor                         -> facts
```

- `image` 返回 stored pixels 与 source orientation。
- `thumbnail` 使用 ImageIO downsample，并可在 decode 时转正方向。
- `transcode` 让 ImageIO 从 encoded source 写入 destination，适合不解码像素的格式、
  quality 与 metadata 改写；满足条件时可使用底层 source-copy 机制。
- `encode` 消费 ImageFrame，写入 quality、选择后的 metadata 与 ImageFrame orientation。

crop、canvas placement、Alpha flatten、output color conversion 与采样风格属于 Rendering；
ImageIO 不重复提供另一套像素编辑 API。

## Options 与 runtime capability

公开 options 是带有图片语义的扁平值，不再依赖人工 namespace：

- `ImageDecodeOptions`
- `ImageThumbnailOptions`
- `ImageTranscodeOptions`
- `ImageEncodeOptions`

Options 是构造后不可变的值。`maximumPixelSize` 有值时至少归一为 `1`；有限的
`compressionQuality` 限制在 `0...1`，NaN 与无穷值归一为 `nil`，表示不覆盖
ImageIO 默认值。

首版仍直接使用 `UTType` 表达 source/destination type。可写能力必须通过
`ImageReader.canEncode(_:)` 查询，不能由 enum case 静态假定；可读能力同理。
package-only `ImageReader.canTranscode(as:options:)` 接收与 `transcode` 相同的完整
`ImageTranscodeOptions`，并同时检查静态图片、destination capability 与 metadata-transcode
限制；它不能对随后必然失败的请求返回 `true`，也不扩大为公共 capability API。

不公开：

- `[CFString: Any]`。
- `CGImageSource` / `CGImageDestination`。
- finalize 生命周期。
- ImageIO `k...` keys。

## Error 边界

独立 product 抛出 `ImageIOError`：

- file read failed。
- invalid image data / inspection unavailable。
- animated source unsupported。
- pixel decode failed。
- metadata transcode unsupported。
- encode failed for destination `UTType`。

`WICompressExecution` 在唯一边界映射为 `WICompressError`。ImageIO 不依赖压缩 Domain，
也不以 `nil`、warning 或 silent fallback 隐藏失败。

## 同步与异步

ImageIO primitives 保持同步：

- 不创建 queue、actor 或全局 executor。
- 不在内部静默切线程。
- 不共享跨请求 ImageReader/destination。

同步调用方自行决定所在执行上下文。未来 `WICompressor` async terminal 负责让完整
`ImagePipeline` 不阻塞 caller actor，并处理 priority、cancellation 与 executor 选择；
同步与异步 terminal 复用相同 ImageReader、Rendering 与编码语义。

## ImagePipeline 集成

`ImagePipeline` 持有一次请求的 ImageReader，并直接使用其 ImageDescriptor。Process 与 Target
仍是 Pipeline 内的两种算法：

```text
Data / URL
  -> ImageReader
  -> ImageDescriptor
  -> Process or Target decisions
  -> ImageReader.image / thumbnail / transcode
  -> optional WIImageRendering
  -> ImageFrame.encode
  -> WIResult
```

ImageReader 不会进入纯 geometry、resizing 或 candidate ranking 函数。Target 在固定几何的
quality search 中复用 rendered pixels；ImageIO chain 不拥有 byte-budget feedback。

## 首版边界

明确不做：

- GIF/动画 frame API、duration、缓存与播放 session。
- public byte-source protocol、加密随机访问 source。
- async ImageIO API、queue、actor、TaskExecutor。
- coder registry、plugin、全局 mutable codec priority。
- crop、resize policy、Rendering chain、Target search。
- HDR/EDR tone mapping 或 gain-map preservation contract。

多帧 source 可以 inspection，但 `image`、`thumbnail` 与 `transcode` 明确抛
`animatedSourceUnsupported`，不会静默只处理 index 0。

## 验证合同

- Data/file ImageReader 的 descriptor、decode、thumbnail 与 transcode 行为一致。
- File ImageReader 不预读完整 bytes；产品 Pipeline 只在 return-original 时读取原始文件。
- raw decode → encode 保留 source orientation。
- transformed thumbnail/rendered frame → encode 写 orientation 1。
- selected metadata 与 MakerNote 独立性正确。
- GPS-only transcode 使用底层 source-copy 机制，不 decode pixels。
- invalid、animated 与 unsupported destination 产生 typed error。
- `WIImageIOTests` 只依赖 `WIImageIO` target，不需要直接依赖 `WIImageDomain`。
