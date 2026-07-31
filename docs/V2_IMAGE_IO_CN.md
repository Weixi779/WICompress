# WICompress 2.0 ImageIO Core

状态：ImageIO、Raster、Process 与 Target 同步执行链路已完成；异步 terminal 尚未实施。

本文记录 WICompress 2.0 对 Apple ImageIO 的内部二次封装方案。它只定义执行基础设施，
不定义 `WIImageProcess` 或 `WICompressionTarget` 的公共产品语义。

相关文档：

- [`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md)：跨产品线 Domain 与 Execution Core
  边界。
- [`V2_IMAGE_PROCESS_CN.md`](V2_IMAGE_PROCESS_CN.md)：正向处理产品线。
- [`V2_COMPRESSION_TARGET_CN.md`](V2_COMPRESSION_TARGET_CN.md)：反向求解产品线。
- [`V2_IMAGE_RASTER_CN.md`](V2_IMAGE_RASTER_CN.md)：ImageIO decode 与 encode 之间的
  像素绘制模块。
- [`V2_CAPABILITY_MAP_CN.md`](V2_CAPABILITY_MAP_CN.md)：1.x 能力、现有实现与外部调研证据。

## 为什么建立独立模块

1.x 的 ImageIO 使用集中在 `WIImageSource`、`WIImageEncoder` 和
`WIImageFormat`，但 source inspection、thumbnail options、destination properties、
render 和 encode 仍然耦合在 WICompress pipeline 中。

这带来三个结构性问题：

1. Process 与 Target 需要复用相同的 source、properties、thumbnail 和 encode 能力，
   但目前只能共同依赖一组同时知道 Domain plan 和 ImageIO 字典的实现。
2. `kCGImageSource...`、`kCGImageDestination...` 与 `[CFString: Any]` 会散落到新的
   resolver、solver 或其他调用点。
3. 重构前的 `WIImageEncoder` 同时负责 ImageIO destination、thumbnail decode、
   Core Graphics render 和 plan path 分派；2.0 需要把 ImageIO 与 Raster 各自的不变量
   交给不同模块。

成熟图片库已经验证 ImageIO 二次封装的价值：

| 参考 | 可借鉴 | 不照搬 |
|---|---|---|
| Nuke 13.0.6 | typed thumbnail options、同步 codec、runtime capability | 展示型二维 Target 与平台图片入口 |
| Kingfisher 8.11.0 | 简洁调用语法、frame/source 的局部封装 | 分散的 helper、含糊的 optional failure |
| SDWebImage 5.21.7 | static/progressive/animated 能力分层 | 全局 mutable coder registry、字符串 options |
| Signal iOS `OWSImageSource` | Data/file source、decode 前 inspection、资源安全事实 | 加密随机访问源与聊天附件限制 |

外部实现只证明这种封装是成熟路径，不决定 WICompress 的能力全集。WICompress 的边界仍
由当前压缩产品线和真实执行路径决定。

## Target 与可见性

独立 SwiftPM target 的依赖位置：

```text
WIImageDomain
    ↑
WIImageIO
    ↑
WICompressExecution
    ↑
WICompress
```

首版约束：

- `WIImageIO` 是 package 内部 target，不声明独立 library product。
- Source、Descriptor、options 与 codec primitives 使用 `package` 访问级别。
- `WIImageFormat` 是唯一公开的 ImageIO 结果事实，由 Source inspection 产生；它不提供
  public Data initializer 或公开 detection terminal。
- 依赖 Foundation、CoreGraphics、ImageIO 与 UniformTypeIdentifiers。
- 不依赖 WICompress 的 Process、Target、solver、Luban 或平台 UI 框架。
- 不使用公共单例、全局 mutable registry、内部 queue 或 actor。

如果未来出现独立的真实消费者，可以重新评估是否发布 product；当前不为假设消费者冻结
公共兼容合同。

## 模块职责

`WIImageIO` 只拥有 ImageIO 固有能力：

| 能力 | 输入 | 输出 |
|---|---|---|
| Source creation | encoded `Data` / file `URL` | scoped source handle |
| Inspection | source properties | typed descriptor / resource facts |
| Static decode | source + typed decode options | `CGImage` |
| Thumbnail decode | source + maximum pixel size | transformed `CGImage` |
| Pixel encode | `CGImage` + representation options | encoded `Data` |
| Source copy | source + destination options | encoded `Data` |
| Runtime capability | type identifier / format | can decode / can encode |

它不拥有：

- Luban、maximum long side、aspect ratio 或 Target sizing 的解释。
- crop、canvas placement、Alpha flatten 和 color render 的 Domain 决定与像素执行。
- quality 搜索、candidate ranking、最大尝试次数或 byte-budget solver。
- passthrough、size guard 或“原图是否已经满足产品合同”的判断。
- async 调度、取消、请求合并、缓存、网络或 UI 生命周期。

## Source 与 Descriptor

`WIImageIO.Source` 是 ImageIO source 的同步、作用域内 handle。它可以持有
`CGImageSource`，但不向调用方暴露该对象。

```swift
package final class Source {
    package init(data: Data) throws
    package init(contentsOf url: URL) throws

    package var byteCount: Int { get }
    package var descriptor: Descriptor { get }

    package func image(
        options: DecodeOptions = .init()
    ) throws -> CGImage

    package func thumbnail(
        options: ThumbnailOptions
    ) throws -> CGImage
}
```

两种入口拥有不同的 byte lifecycle：

- Data source 直接保留调用方提供的 encoded bytes。
- File source 直接从 URL 创建 ImageIO source，不预先执行 `Data(contentsOf:)`。
- `byteCount` 不要求 file source materialize 完整 Data。
- 只有 passthrough 最终确实需要返回原始文件内容时，才读取完整 Data。
- sync terminal 在当前上下文完成必要的文件读取；async terminal 由 WICompress 在工作任务
  中完成，不改变 `WIImageIO` primitive 的同步语义。

首版不建立通用 `WIImageByteSource` protocol，也不接受 arbitrary random-access 或加密
来源。若未来出现真实的加密附件消费者，再根据基准和生命周期要求评估
`CGDataProvider` bridge，不为当前 Data/URL 两种输入提前建立协议。

已接受的命名：

- 使用 `image()` 和 `thumbnail(options:)`。
- 不使用 `makeImage()`、`createImage()` 或 `decodeImage()`。
- 两者是可能失败并执行实际 decode 的方法，不是暗示廉价访问的属性。
- 首版不暴露 `image(at:)` 或 `thumbnail(at:)`；没有多帧产品合同。

`WIImageIO.Descriptor` 是可跨并发域传递的 source facts，至少覆盖：

```text
exact UTType
coarse result format
pixel size
oriented pixel size
orientation
frame count
has alpha
supported metadata categories
gain-map presence
```

descriptor 不包含调用方 Policy、UI point、scale、Luban 结果或目标输出要求。需要创建
bitmap 才能确认的颜色信息可以按需读取，不要求 source 初始化时完整 decode。
容器是否可读写是当前运行环境的 capability，不复制进每个 descriptor。

### Resource Facts 与 Limits

Signal 的实现证明 decode 前统一检查尺寸和预计内存是有价值的，但“检查事实”与“决定
业务上限”属于不同所有者。

`WIImageIO` 负责安全地产生或验证基础事实：

- encoded byte count。
- 正数 pixel width / height。
- pixel count 的 checked arithmetic，不允许整数溢出。
- frame count。
- 可以从 properties 可靠取得时的 bit depth、color model 或预计 decoded byte count。
- ImageIO 能否建立 source、读取 properties 和创建目标 bitmap。

WICompress Execution 或更高层调用方负责决定限制：

- 允许的最大输入字节数。
- 允许的最大 pixel count 或预计 decoded memory。
- 是否接受特定 color model。
- 达到资源上限时的产品错误和 fallback。

`WIImageIO.Source` 首版不内置 Signal 聊天附件使用的固定阈值，也不新增 public
`WIImageLimits`。压缩库可能需要处理对聊天应用过大但仍然合法的源图；没有明确资源预算
前，外部项目的阈值不能自动成为 WICompress Requirement。

## Decode 与 Thumbnail Options

ImageIO options 使用强类型值，不向 WICompress 暴露 `[CFString: Any]`：

```swift
package struct DecodeOptions: Hashable, Sendable {
    package var cacheImmediately: Bool
}

package struct ThumbnailOptions: Hashable, Sendable {
    package var maximumPixelSize: Int?
    package var appliesOrientationTransform: Bool
    package var cacheImmediately: Bool
}
```

这些 options 已按当前实现冻结为 package-only 值类型。

`WIImageIO` 不提供：

```swift
.fit(within: ...)
.fill(...)
.fitInside(...)
.alignment(...)
```

这些名称会重新混合 UI 展示、尺寸算法与像素操作。ImageIO 层只接收上层已经计算完成的
concrete pixel value，例如 `maximumPixelSize`。如何从源尺寸、Luban、完整目标宽高或
Target sizing 得到该值，属于 Size Calculation 或 Execution Plan。

Thumbnail 应默认只缩小、不隐式放大；最终合同由调用它的 Execution Plan 决定。

## Encode 与 Source Copy

编码保留两种不同语义：

```text
CGImage -> pixel encode -> Data

WIImageIO.Source -> copy from source -> Data
```

Pixel encode 用于已经由 `WIImageRaster` 完成 resize、crop、Alpha flatten 或 color
render 的位图。
Source copy 用于需要 ImageIO 从原 source 复制像素和允许 metadata 保留的路径。两者不能
为了 API 对称合并成一个含糊的万能函数。

内部边界统一使用 `UTType` 表达精确容器，只有最终 `WIResult` 把它归类为公开的
`WIImageFormat`。`Encoder` 和 source copy 都接收 `WIImageMetadataOptions`，并在
ImageIO 边界把类别选择映射为 properties。`.preserve.subtracting(.gps)` 在不要求
像素或 quality 变化时使用 `CGImageDestinationCopyImageSource` 无损移除 GPS，不进入
Raster；它不承诺清除厂商 MakerNote 或自定义 XMP 中的潜在位置字段。`.strip` 与普通
metadata 子集遇到未建模 metadata 时必须进入 pixel encode，不能误走 passthrough；
当前不把独立的 XMP graph 暴露到公共 Domain。

Destination 的 create、add 和 finalize 是一次同步、有序生命周期：

- destination 只在一次 encode/copy 调用内部存在。
- destination 不跨 Task、actor 或线程共享。
- finalization failure 必须显式抛错。
- runtime capability 不能由静态 format case 假定。

Destination properties、compression quality、orientation 与 metadata dictionary 的
底层映射由 `WIImageIO` 负责；产品层只提供已经解析好的输出要求。

## 同步与并发模型

ImageIO primitive 保持同步：

```text
Data / file URL + Sendable options
    -> create scoped source
    -> inspect / image / thumbnail
    -> WIImageRaster when required
    -> create scoped destination
    -> encode / finalize
    -> Data
```

并发边界：

- `WIImageIO.Source` 是 scoped handle，不承诺 `Sendable`。
- descriptor、format 和 options 使用不可变或值语义，并保持 `Sendable`。
- 同一个 source/destination 的操作由单一调用上下文有序执行。
- 不同顶层压缩调用各自创建 source/destination，可以由 `WICompressor` async
  execution 并发。
- 不建立全局串行 ImageIO queue。
- async terminal API 只把 `Data`、URL 与 `Sendable` 配置带入工作任务，不跨 actor
  传递活跃的 source/destination。

同步 API 在当前调用上下文执行。异步 API 的取消、优先级和 executor 选择属于
`WICompressor` terminal execution，不在 `WIImageIO` 内重复设计。

## 与 Execution Core 的关系

`WIImageIO` 不是新的公共 pipeline，也不解释 Domain。完整方向是：

```text
WIImageProcess ────────┐
                       ├─> resolver / solver
WICompressionTarget ───┘
                              ↓
                   concrete Execution Plan
                              ↓
                WIImageIO inspect / decode
                              ↓
                 WIImageRaster.image when needed
                              ↓
                    WIImageIO encode / copy
                              ↓
                             Data
```

Raster 与 ImageIO primitive 分属两个内部能力，但对外仍是一次 terminal execution 和
一次最终编码。`WIImageIO` 不提供 public chain，也不把中间 `CGImage` 生命周期交给
WICompress 的普通调用方。Raster 的 resolved-geometry 输入、单次绘制和 surface
生命周期以 [`V2_IMAGE_RASTER_CN.md`](V2_IMAGE_RASTER_CN.md) 为准。

Target solver 可以在一次顶层调用中复用同一个 source，并在相同尺寸的 quality search
中复用已经 render 的 `CGImage`。这也是不能只保留静态
`ImageIOCodec.inspect/decode/encode(Data, ...)` facade 的原因：one-shot API 会重复创建
source，或把缓存生命周期隐藏进静态类型。

## Error 边界

ImageIO 层使用 typed throws 表达基础设施失败，至少能够区分：

- invalid image data。
- source properties unavailable。
- image / thumbnail creation failed。
- unsupported source or destination representation。
- destination creation failed。
- destination finalization failed。
- animated source unsupported。

`WIImageIO.Error` 在基础设施边界表达这些失败，`WICompress` 在产品边界统一映射为
`WICompressError`；ImageIO 层不以 `nil`、warning 或 silent fallback 隐藏失败。

## 迁移方向

这是一轮 scoped reconstruction，不是新增第三条产品线。

| 1.x 位置 | 2.0 归属 |
|---|---|
| `WIImageSource` 中的 source creation 和 properties 读取 | `WIImageIO.Source` / `Descriptor` |
| URL 入口中的 eager `Data(contentsOf:)` | File-backed `WIImageIO.Source`，仅在需要原始 Data 时读取 |
| `WIImageFormat` 的 type detection 与 runtime writability | `WIImageIO` Format / Capabilities |
| `WIImageEncoder` 中的 thumbnail options | `WIImageIO` Thumbnail |
| `WIImageEncoder` 中的 destination create/add/finalize | `WIImageIO` Encode / Copy |
| bitmap/canvas/color render | `WIImageRaster` |
| `WIWritePlanResolver` 的 Domain 决策 | 由 2.0 Process / Target resolver 替换 |
| `WICompressionSolver` 的 candidate search | Target Domain 保留 |

当前迁移后，WICompress target 已不再直接拼接 ImageIO source/destination option
dictionary，也不再持有 bitmap render/orientation normalization helper。旧执行路径已经
删除，不在其上增加长期兼容 wrapper。

## 首版非目标

- 不支持 GIF、APNG、animated HEIC 或其他多帧图片处理。
- 不提供 frame source、`image(at:)`、frame duration 或动画播放能力。
- 不提供 incremental / progressive decode session。
- 不提供 codec protocol、插件、priority chain 或全局 coder registry。
- 不提供 HDR/EDR 专属 options 或 tone mapping Domain。
- 不提供任意 metadata dictionary mutation。
- 不公开 `CGImageSource`、`CGImageDestination` 或 raw ImageIO dictionary。
- 不发布独立 `WIImageIO` library product。
- 不在 `WIImageIO` 内提供 async API、queue、actor 或 cancellation。
- 不提供 UI image、point/scale、content mode 或 Photos adapter。
- 不提供 arbitrary random-access、加密文件或公开 byte-source protocol。
- 不内置来源于特定 App 的输入字节、pixel count 或 decoded-memory 固定阈值。

多帧图片的首版行为是 inspect frame count 后明确返回
`animatedSourceUnsupported`。GIF/动图也不属于当前长期规划；仅当未来出现明确的压缩
产品场景和消费者时才重新打开，而不是因为参考库拥有该能力。

## 验证合同

独立模块至少需要覆盖：

- JPEG、PNG、HEIC 的 format detection 与 runtime encode capability。
- pixel size、orientation、Alpha、frame count 与 metadata inspection。
- Data source 与 file source 的 descriptor、decode 和 encode 结果一致。
- file source 可以取得 `byteCount`，且创建 source 不预先 materialize 完整 Data。
- 非正尺寸、pixel-count arithmetic overflow 与无法安全检查的 source 明确失败。
- invalid data 和 animated source rejection。
- full image decode。
- thumbnail 最大像素限制、orientation transform 和不隐式 upscale。
- pixel encode 的 format、quality、Alpha 与 finalization failure。
- source copy 的 metadata/orientation 行为。
- GPS-only metadata 过滤不解码像素，并保持 source orientation。
- WICompress 两条产品线经过同一个 ImageIO execution path。
- 需要像素变化的路径经过同一个 `WIImageRaster.image` 入口。
- sync 与 async terminal 对相同输入、配置和错误具有一致结果。

测试继续使用真实 fixture 验证 ImageIO 行为，纯尺寸计算不依赖 ImageIO fixture。

## 已冻结合同

- 独立、非 product 的 `WIImageIO` target。
- package-only typed API。
- scoped、非 `Sendable` 的 source handle。
- Data/file URL 双入口；file source 不预读完整 Data，passthrough 时才按需读取。
- `byteCount` 与 decode 前资源事实属于 source/inspection。
- arbitrary random-access、加密 source 和固定资源阈值不进入首版。
- `image()` 与 `thumbnail(options:)` 命名。
- typed descriptor、options 与 runtime capability。
- exact container 使用 `UTType`，公开结果使用 `WIImageFormat` 粗分类。
- metadata 使用可组合的 `WIImageMetadataOptions`，不暴露 raw dictionary。
- 同步 primitive、上层并发调度、无全局串行 queue。
- raw ImageIO dictionary 与 CF source/destination 不越过模块边界。
- 静态图片首版；GIF 和其他动图不在当前规划。
- ImageIO 只拥有 representation 基础设施，Raster 独立拥有像素绘制。
