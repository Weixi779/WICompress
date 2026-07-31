# WICompress 2.0 Domain Model

状态：共享 Domain 边界已冻结；各产品线的具体合同分别维护。

本文是 WICompress 2.0 跨产品线架构边界的单一来源。它只记录
`WIImageProcess` 与 `WICompressionTarget` 共同依赖的已接受结论，不承载调研过程，
也不提前冻结尚未讨论清楚的 Swift API。

相关文档：

- [`V2_IMAGE_PIPELINE_CN.md`](V2_IMAGE_PIPELINE_CN.md)：2.0 内部状态、执行决策与
  ImageIO/Raster 编排的最终边界。
- [`V2_CAPABILITY_MAP_CN.md`](V2_CAPABILITY_MAP_CN.md)：1.x 能力盘点、组合证据与外部调研。
- [`V2_IMAGE_PROCESS_CN.md`](V2_IMAGE_PROCESS_CN.md)：已冻结的 `WIImageProcess`
  合同。
- [`V2_COMPRESSION_TARGET_CN.md`](V2_COMPRESSION_TARGET_CN.md)：已冻结的
  `WICompressionTarget` 合同。
- [`V2_IMAGE_IO_CN.md`](V2_IMAGE_IO_CN.md)：公开 ImageIO product、同步 typed chain
  与执行层迁移边界。
- [`V2_IMAGE_RASTER_CN.md`](V2_IMAGE_RASTER_CN.md)：package-only Raster target、单次
  crop/resize 绘制与 bitmap surface 边界。

## 产品边界

WICompress 是图片像素处理与编码压缩库，不拥有 View、页面布局、网络加载、缓存、
Photos 权限或平台分享业务。

2.0 保持两条公共产品线：

| Domain | 控制方向 | 调用方拥有 | 库拥有 | 成功合同 |
|---|---|---|---|---|
| `WIImageProcess` | 正向执行 | 确定的处理和编码要求 | 如何融合并执行 | 按声明执行一次，不保证最终 byte count |
| `WICompressionTarget` | 反向求解 | maxBytes、sizing 上界和不可变输出要求 | candidate scale、quality、尝试和选择 | 最终 `byteCount <= maxBytes` |

两条线不建立万能 Request，也不让 Target 继承或包装 Process。它们可以共享底层值和执行
机制，但不能为了复用类型混淆控制权：

```text
WIImageProcess ────────┐
                       ├──> internal ImagePipeline
WICompressionTarget ───┘       ├──> ImageIO
                               └──> Raster
                                      ↓
                                   WIResult
```

Process 与 Target 是同一 Pipeline 内的两种算法；内部状态和编排以
[`V2_IMAGE_PIPELINE_CN.md`](V2_IMAGE_PIPELINE_CN.md) 为准。

公共模型按所有权拆分：`WIImageDomain` 保存像素、颜色、格式与 metadata 等共享图片事实；
`WICompressDomain` 保存 Process、Target、Output、crop 与 resizing 等压缩请求语义。
`WIImageFormat` 只描述容器家族，ImageIO 负责检测；`WICompressError` 属于
`WICompressDomain`，表达请求构造、resizing 扩展点和 terminal 失败。
独立 `WIImageIO` 产品使用 `WIImageIO.Error`，Execution 在 Pipeline 边界完成映射。

## Domain 所有权

| Domain | 拥有的事实或决定 | 不拥有 |
|---|---|---|
| Source Inspection | format、byte count、pixel size、orientation、Alpha、frames、metadata、gain map | 按需 source color、runtime capability、调用方 Policy、UI scale |
| Size Calculation | 根据完整源像素返回完整目标宽高 | ImageIO 编码、View content mode |
| Crop Calculation | 根据 concrete ratio 与 normalized anchor 返回 source pixel rect | resizing、quality、UI alignment |
| Image Processing | concrete crop、resize、方向和颜色渲染 | maxBytes 搜索、平台分享意图 |
| Output | container、Alpha 处理、metadata、output color | Target 的 candidate ranking |
| Process | 调用方选择的 sizing、pixel operation、quality 和 output | 最终 byte 上限 |
| Target | maxBytes 合同与候选搜索 | 调用方固定 quality、UI placement |
| Image Pipeline | 持有一次调用的 source facts、执行决策与工作像素生命周期 | 对外扩展节点或 UI 语义 |

Quality 的所有权随产品线变化：在 Process 中由调用方决定，在 Target 中由内部搜索算法决定。
因此 quality 不能仅为了字段复用而被无条件塞进共享 Output。

## 共享 Output Domain

`WIImageProcess` 与 `WICompressionTarget` 使用同一个 Output 值。Output 拥有最终编码
期间不可随意改变的三组要求：

```text
Output
├── representation：容器选择与必要的 Alpha 处理
├── metadata
└── color space
```

Quality 不属于 Output。共享类型也不声明跨产品线的全局默认值：

| 产品线 | Representation 默认 | Metadata 默认 | Color Space 默认 |
|---|---|---|---|
| Process | preserve source container | strip | preserve |
| Target | PNG when Alpha, otherwise JPEG | strip | convert to sRGB |

### Representation 与 Alpha

Alpha 不作为 Output 顶层平级 Policy。它只在目标表示无法保留透明像素时，由对应
representation 明确处理：

| Representation 语义 | 透明源行为 |
|---|---|
| preserve source container | 保持源容器能够表达的 Alpha |
| JPEG | 明确失败，不静默丢弃 Alpha |
| JPEG flattened over an opaque color | 在显式不透明背景上合成后编码 |
| PNG | 保留 Alpha |
| HEIC | 按目标容器能力验证 |
| PNG when Alpha, otherwise JPEG | 有 Alpha 选择 PNG，无 Alpha 选择 JPEG |

`pngIfAlphaOtherwiseJPEG` 对应的语义作为常用一等能力保留，不折叠进含糊的
`automatic`。最终 case 名称和 Swift 拼写在 API 阶段冻结。

两条产品线共享同一套 Output 解释规则与 typed errors：

- JPEG 遇到透明源且未显式铺底。
- JPEG background 不是 opaque color。
- 当前平台不能写入目标 representation。
- ICC Profile 无效或明确 color conversion 无法兑现。

Pipeline 不使用 warning 或静默换格式满足合同。

### Metadata

Metadata 使用一个可组合的 `WIImageMetadataOptions: OptionSet`：

- `.exif`
- `.gps`
- `.iptc`
- `.tiff`
- `.makerNotes`

`.strip` 是空集合，仍是默认上传/压缩行为；`.preserve` 是当前支持类别的完整集合。
调用方通过标准集合运算表达选择，不引入逐字段 rule 对象或 metadata resolver：

```swift
let metadata = WIImageMetadataOptions.preserve.subtracting(.gps)
```

`.makerNotes` 同时覆盖 ImageIO 的顶层厂商字典与 Exif 字典内嵌 MakerNote；它与
`.exif` 独立选择，排除 `.makerNotes` 时不会因保留 Exif 而把内嵌内容带回输出。
`.gps` 只承诺 ImageIO 暴露的标准 GPS properties，不把厂商 MakerNote 或自定义 XMP
中的潜在位置字段伪装成同一能力。需要隐私清理时应使用 `.strip`；当前不把 XMP graph
公开为 OptionSet case。

颜色 profile 不属于 metadata，它是显示语义，继续由 Output Color Space 所有。
orientation 也不属于可删除的 metadata 类别：source-copy 保持方向语义，render 路径把
方向烘焙进像素并写为 `1`。

### Color Space

Output Color Space 只保留两个决定：

```text
preserve
convert to a concrete color space
```

Concrete Color Space 至少支持 sRGB、Display P3 与 custom ICC Profile。最终使用 enum
还是 struct 尚未冻结，但 custom ICC 必须保留为开放值入口。

2.0 删除 public `preserveIfSupported`。当前实现中的该 case 只是检查源空间是否位于
调用方 Set，再决定 preserve 或转换 fallback；它不代表 ImageIO capability negotiation。

2.0 也不提供候选数组、`preferred`、自动协商或 public color-space resolver。若未来出现
真实需求，应先公开必要的 source color facts，让调用方把自己的数组、Set 或配置规则
解析为一个 concrete preserve/convert 决定，再交给 Output。

## 已冻结的公共边界

| 决策 | 说明 |
|---|---|
| 不再使用统一 `Policy` 容器 | sizing、pixel operation、output、quality 和 constraint 不是同一类决定 |
| 对外 API 保持窄和简单 | 内部层级和执行路径不泄漏给普通调用方 |
| 不提供公共单例 | 对外使用静态 facade 或值语义入口 |
| 不提供 public Processor Chain | 链式没有降低 Domain 理解成本，还会暗示固定执行顺序 |
| 不提供开放节点 Pipeline | 2.0 没有自定义处理节点或插件生态 Requirement |
| 描述与执行分开 | 配置是同步纯值；一次 terminal call 才开始工作 |
| 同步与异步入口并存 | 同一语义和 engine；同步在当前调用上下文执行，异步不占用 caller actor |
| 2.0 最低 Swift 6.2+ | 需要旧工具链的调用方继续使用 1.x |
| Core 保持 UIKit/AppKit-free | 裸 Data 不拥有 View、point 或 Retina scale 语义 |
| 核心尺寸统一使用整数 pixel | point-to-pixel 转换属于知道 UI 上下文的外层 |
| Source inspection 与 pixel decode 分开 | 读取 properties 不要求提前创建完整 bitmap |
| 不公开长期 `ImageResource` 生命周期 | 调用方不拥有 `CGImageSource`、`CGImage` 或内部 Task |
| `fit`、`fill`、`fitInside`、alignment 退出核心 Domain | 这些名称混合了 UI 展示、尺寸约束和像素处理 |
| Resizing 是完整 PixelSize 到 PixelSize 的插槽 | 调用方可使用内置算法或自定义实现，Pipeline 不解释半成品 ratio 或长边 |
| 压缩处理不隐式 upscale | 内置压缩 resizing 默认只缩小；调用方显式选择或实现允许放大的 resizer 时可以放大 |
| Crop 使用 normalized anchor | 左上原点、`x/y` 位于 `0...1`、默认中心；不公开九宫格方位枚举 |
| Crop 先于 resizing 解析 | resizing 接收裁后完整尺寸，底层仍可一次绘制 |
| crop 属于像素处理 | ImageIO 没有 crop option；实际由 Core Graphics 完成 |
| 一次调用只进行一次最终编码 | resize、crop 和 render 在像素阶段融合，不产生中间编码 Data |
| metadata 默认 strip | 符合压缩上传的主要方向 |
| metadata preserve 是 best effort | 不承诺逐项、逐字节或 gain map 完整不变 |
| Process 与 Target 共享 Output | 共享 representation、metadata 和 color space，不共享 quality 或默认值 |
| JPEG 默认拒绝透明源 | Alpha flatten 必须显式提供 opaque background |
| `pngIfAlphaOtherwiseJPEG` 保留 | 它是常用、确定的 representation selection，不是含糊 automatic |
| Color Space 只保留 preserve/convert | sRGB、Display P3 和 custom ICC 覆盖当前真实范围 |
| 内部模块按真实能力解耦 | 不为了组件化建立没有不变量、生命周期或第二实现的空协议 |
| ImageIO 模块边界已冻结 | 独立公开 product、`Reader → Frame → encode` typed chain、同步 primitive |
| Raster 模块边界已冻结 | 独立 package target、唯一 `image` 入口、隐藏 bitmap surface，不发布 product |
| ImageIO 与 Raster 实现后置 | 由已冻结的 Process、Output 和 Target 合同反推最终执行层输入 |
| 静态图片是当前范围 | GIF、其他动图、增量和多帧 session 不属于当前规划 |
| 2.0 不保持旧 geometry 源码兼容 | 旧工具链和旧语义调用方继续使用 1.x |

## 执行层边界

ImageIO 与 Raster 是执行机制，不是公共 Domain 的定义者。模块和并发边界详见
[`V2_IMAGE_IO_CN.md`](V2_IMAGE_IO_CN.md) 与
[`V2_IMAGE_RASTER_CN.md`](V2_IMAGE_RASTER_CN.md)。2.0 不从现有
`WICompressOptions`、`WIWritePlan` 或四条 write path 反推新 API。

上层冻结后，ImagePipeline 持有 source facts，并把 Domain 意图解释成具体执行参数：

```text
source facts
+ fixed source pixel rect
+ concrete destination pixel size
+ immutable output requirements
+ optional lossy quality
    -> inspect
    -> ImageIO image / thumbnail
    -> ImageRaster.image when pixels must change
    -> ImageIO encode / source copy
    -> encoded result
```

Luban、custom resizing、aspect ratio、anchor、Target ranking 和平台限制都由
Pipeline 内对应算法解释。ImageRaster 只接收 concrete geometry，不重新提供 `fit`、
`fill` 或第二套 processing policy。

## 当前非目标

- 不在 2.0 首轮优化 Target solver 算法或公开其参数。
- 不为了组件化公开所有内部类型。
- 不建立自定义 Processor、节点注册或插件系统。
- 不内置微信、QQ、微博等平台分享 preset。
- 不在 Core 接入 UIKit、AppKit、Photos 或 PhotosUI。
- 不在 Core 建模 View content mode、页面位置或九宫格 alignment enum。
- 不根据 DPI、文件名或图片字节猜测 `@2x/@3x` UI scale。
- 不提供 Color Space candidate preference 或自动 capability negotiation。
- 不在 2.0 首轮扩展动图压缩和新的输出容器。

## 重新打开条件

以下结论只有出现新的真实消费者或失败证据时才重新讨论：

- 需要 public chain 或自定义处理节点。
- 需要长期存在并跨调用复用的 public image resource。
- 需要任意 source pixel rect、canvas placement 或 Core 内的 UI point 单位。
- 需要 Target 或默认 resizing 隐式 upscale。
- 需要 Target 平台 preset 或公开 solver ranking 参数。
- 需要库在多个 Color Space 候选之间进行运行时协商。
