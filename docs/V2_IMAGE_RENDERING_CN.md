# WICompress 2.0 Image Rendering Core

状态：独立 `WIImageRendering` target、单次绘制入口以及 Process/Target Pipeline 集成均已
完成。

本文记录 WICompress 2.0 对 Core Graphics 像素绘制能力的内部二次封装。它位于 ImageIO
decode 与 encode 之间，只执行已经解析完成的几何和输出决定，不定义
`WIImageProcess`、`WICompressionTarget` 或 UI 展示语义。

内部状态与编排已经由
[`V2_IMAGE_PIPELINE_CN.md`](V2_IMAGE_PIPELINE_CN.md) 重新冻结；本文出现的
resolver、solver、Execution Plan 和 Execution Core 仅属于历史迁移背景。

相关文档：

- [`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md)：跨产品线 Domain 与执行边界。
- [`V2_IMAGE_PROCESS_CN.md`](V2_IMAGE_PROCESS_CN.md)：crop 与 resizing 的公共合同。
- [`V2_COMPRESSION_TARGET_CN.md`](V2_COMPRESSION_TARGET_CN.md)：Target 固定裁切与
  反馈搜索边界。
- [`V2_IMAGE_IO_CN.md`](V2_IMAGE_IO_CN.md)：inspect、decode、transcode 与 encode。

## 为什么独立封装

1.x 的 Core Graphics 绘制位于 `WIImageEncoder` 内部，与 ImageIO destination、write
path、Domain plan 和编码错误混合。2.0 增加明确的 crop/resizing 插槽后，下面这些
不变量需要单一所有者：

- orientation 到视觉像素坐标的转换。
- crop 与 resize 的单次重采样。
- bitmap context、pixel format、row alignment 和 buffer 生命周期。
- Alpha、opaque background、output color space 和 standard-range surface。
- Core Graphics 左下原点与公开图片左上原点之间的转换。

Telegram、Nuke、Signal、SDWebImage 和 Kingfisher 的成熟实现共同证明这种 primitive
有真实价值。其中 Nuke、Signal 和 Telegram 都使用最终目标画布上的超界 draw rect，
一次完成 crop 与 resize；Telegram 进一步集中管理 bitmap surface 和 backing buffer
生命周期。

外部实现只验证底层方向，不决定 WICompress 的公共 API。WICompress 不复制通用
DrawingContext、UIKit renderer、processor chain 或 UI placement。

## Target 与可见性

新增独立、非 product 的 package target，本文概念上称为 `WIImageRendering`：

```text
WIImageDomain ────────┐
                     ▼
WIImageIO ── decode ──┤
                     ▼
                 WIImageRendering
                     │
                     └── render
                           │
                           ▼
WIImageIO ── encode ◀── CGImage
```

首版约束：

- target 不声明独立 library product。
- 跨 target 只暴露一个 package-level 图片绘制入口。
- 不依赖 Process、Target、solver、Luban、UIKit 或 AppKit。
- primitive 保持同步，不拥有 queue、actor、Task 或 cancellation。
- target 命名为 `WIImageRendering`，唯一入口为 `ImageRenderer.render`；通用像素事实来自
  `WIImageDomain`，Rendering 只保留具体的 `ImageRenderRequest` 与 surface 执行选项。

## 唯一模块入口

调用层只看见一个 terminal pixel operation，概念 API 为：

```swift
let image = try ImageRenderer.render(
    decodedImage,
    request: ImageRenderRequest(
        canvasSize: resolvedCanvasSize,
        sourceRect: resolvedCropRect,
        destinationRect: resolvedDestinationRect,
        orientation: sourceOrientation,
        alphaMode: resolvedAlphaMode,
        canvasBackground: resolvedCanvasBackground,
        imageBackground: resolvedImageBackground,
        colorSpace: resolvedColorSpace
    )
)
```

`ImageRenderRequest` 是 immutable execution value，只包含已经解析完成的事实：

```text
source orientation
oriented source pixel rect
final canvas pixel size
destination pixel rect
resolved alpha mode
resolved canvas background
resolved image-area background
resolved output color space
```

原始 `CGImage` 是 `ImageRenderer.render` 的独立输入，不属于 `ImageRenderRequest`。

它不包含：

- `fit`、`fill`、`fitInside` 或 content mode。
- aspect ratio、anchor、Luban 或 `WIImageResizing`。
- `maxBytes`、quality search、candidate ranking 或 retry。
- representation、metadata 或编码格式选择。

Rendering 不再解释 Domain。上层 `ImagePipeline` 负责把 crop、resizing 和 Output 转换为
concrete geometry，Rendering 只执行。

## BitmapCanvas 是隐藏实现

`ImageRenderer` 校验一次完整的 `ImageRenderRequest`，然后建立 request-local
`BitmapCanvas`。它不是转发层：它持有唯一 `CGContext`，并拥有 surface 从创建、绘制到
一次性 finalize 的生命周期。

`BitmapCanvas` 当前拥有：

- checked row-byte 与 total-byte 计算。
- standard-range bitmap format。
- 由 Core Graphics 管理的 row alignment 和 buffer allocation。
- top-left request 到 Core Graphics 坐标的单点转换。
- transparent clear、canvas fill 与 image-area fill。
- scoped `CGContext` 生命周期。
- 一次性 snapshot/finalize。

实现不向外暴露 raw pointer、bitmap info、`CGContext` builder 或可复用 mutable
surface。

## 坐标与 Orientation

Rendering 接收的 `sourceRect` 使用 oriented image pixel coordinates：

- 原点在左上。
- x 向右增加。
- y 向下增加。
- rect 必须落在 oriented source 的有效像素范围内。

Rendering 内部统一处理原始 `CGImage` pixel storage、EXIF orientation 和 Core Graphics
坐标系。输出总是：

```text
orientation = up
pixel size = resolved destination size
coordinate meaning = top-left image coordinates
```

调用层不直接对未 bake orientation 的 `CGImage` 使用视觉 crop rect，也不接触
`flip: Bool` 之类同时混合多个坐标概念的开关。

## Crop 与 Resize 只绘制一次

Rendering 不先创建 crop image 再 resize。它创建最终目标大小的 bitmap surface，计算 source
到 destination 的映射并执行一次 `CGContext.draw`；超出最终画布的部分由 clip 丢弃。

例如 `400 × 300` 的 source 需要生成 `100 × 100` 的中心正方形：

```text
scale    = max(100 / 400, 100 / 300) = 1 / 3
drawSize = 133.33 × 100
drawRect = (-16.67, 0, 133.33, 100)
```

这一次绘制同时完成 orientation bake、crop、resize、background 和 color render，不产生
中间 encoded `Data`，也不产生长期保留原始大图的 crop view。

`CGImage.cropping(to:)` 只在未来确实需要独立无重采样子图时重新评估。当前 Process 和
Target 都会继续 resize 或 encode，不需要公开 subimage/materialized-crop API。

## Background、Alpha 与 Color

Rendering 接收的是 `ImagePipeline` 已经解释完成的 Output facts，不拥有第二套公开 Policy。

Alpha mode 只有两个互斥状态：

```text
preserve
opaque
```

- preserve 使用带 premultiplied Alpha 的 surface，并保证初始像素清零。
- opaque 使用无 Alpha surface。
- `canvasBackground` 填充整个最终画布，例如 exact-canvas 的留白。
- `imageBackground` 只填充 source 的 destination rect，例如透明 PNG 转 JPEG 时的
  Alpha flatten。
- 两层 background 可以同时存在，不能合并成一个值；现有 exact-canvas JPEG 行为依赖
  这一差异。
- JPEG Alpha flatten 只有在 Output 已显式选择 opaque background 时进入 opaque。

首版 surface 使用 standard-range、8-bit canonical RGB layout。sRGB 是压缩输出的稳定
基线；preserve、Display P3 或 custom ICC 是否可兑现由 `ImagePipeline` 结合 ImageIO
capability 决定，再传入 Rendering。HDR、EDR 和 tone mapping 不伪装成普通 color 或
quality 选项。

## Sampling

Core Graphics interpolation 是 backend hint，不是跨平台、跨系统的算法保证。2.0 不公开：

```text
pixelArt
preview
photo
CGInterpolationQuality
```

WICompress 当前只有压缩图片这一种真实 sampling 场景。首版使用一个内部默认映射，并在
未来算法 benchmark 中校准。只有出现第二种真实消费者或需要固定 vImage/Lanczos backend
时，才建立新的 sampling Domain。

## 内存与生命周期

创建 bitmap 前使用 overflow-safe 的 aligned row-byte 估算执行 preflight。创建完成后，
局部 bitmap 成本使用：

```text
estimatedBitmapByteCost = bytesPerRow × height
```

该值只称为 estimate，不承诺等于 resident memory：

- lazy ImageIO image 可能尚未完整 decode。
- provider 或 snapshot 可能共享内存。
- crop view 会保留 parent image。
- encoded Data 与 decoded bitmap 是不同成本。

Surface 生成 `CGImage` 后不继续绘制同一 context，避免不必要的 copy-on-write。若未来
引入 external backing buffer，只能通过 scoped mutable bytes 和一次性 finalize 转移所有权，
不能返回可逃逸的 `UnsafeMutableRawPointer`。

## 同步与并发

Rendering primitive 同步执行，并只在一次 terminal 调用的当前执行上下文中存在：

```text
sync WICompress  -> 当前调用上下文调用 Rendering
async WICompress -> 工作任务调用同一个 Rendering
```

不同顶层调用可以并发创建各自 surface；同一个 context 不跨线程、Task 或 actor 共享。
Rendering target 不建立全局串行队列。

## 与完整执行链的关系

```text
Data / file URL + Process / Target
              │
              ▼
       request ImagePipeline
          │             │
          │             └── WIImageIO transcode / original passthrough
          ▼
   WIImageIO image / thumbnail
          │
          ▼
    ImageRenderer.render
          │
          ▼
     WIImageIO encode
          │
          ▼
         Data
```

ImageIO 的美感来自 inspect、image、thumbnail、encode 等离散 representation 能力；
Rendering 的美感来自把有状态的 Core Graphics machinery 压缩成一次准确的 `render` 操作。
两者不强求相同的内部形态。

## 首版非目标

- 不发布公共 Core Graphics wrapper 或绘图库。
- 不提供 public chain、Canvas DSL 或任意绘制命令。
- 不公开 `CGContext`、raw bitmap info、pixel pointer 或 backend registry。
- 不提供 View point、display scale、content mode 或页面 alignment。
- 不提供圆角、滤镜、模糊、水印、文字、二维码或任意 compositing graph。
- 不提供 Core Image、Metal、vImage backend 自动路由。
- 不提供 HDR/EDR、tone mapping 或任意 pixel format builder。
- 不提供独立 crop view 或长期 bitmap cache。

## Phase 3 验证结果

独立模块与现有集成当前覆盖：

- 八种 EXIF orientation 与 ImageIO display transform 一致。
- normalized top-left crop rect 映射到正确像素区域。
- crop、resize、orientation、background 与 color 在最终 destination surface 中完成。
- canvas background 与 JPEG image-area background 保持独立。
- transparent PNG、JPEG flatten、sRGB/P3 conversion、CMYK fallback 与 metadata
  路径通过原有真实图片回归测试。
- 非正 canvas、无效 rect、越界 rect 与整数溢出在创建 context 前失败。
- Pipeline 在固定 geometry 的 quality search 中只 render 一次，并复用同一个
  `CGImage`。

async terminal 尚未进入公共 API，因此 sync/async parity 留给 execution phase；实际
row padding 的观测与固定内存预算留给后续 benchmark，不扩大当前 Rendering 返回值。

## 已冻结与延后

已冻结：

- 独立、非 product 的 Rendering target。
- package 调用层只有 `ImageRenderer.render` 一个入口。
- bitmap surface machinery 不越过该入口。
- Rendering 只消费 resolved geometry/output，不解释 Domain。
- top-left oriented pixel coordinates，输出 orientation 恒为 `.up`。
- crop + resize + orientation + background + color 单次绘制。
- pixel-only、同步 primitive、无全局队列。

延后：

- 未来是否发布独立 Rendering product 与 public request surface。
- 内部 interpolation 的 benchmark 结果。
- async terminal 建立后的 sync/async parity gate。
- raw mutable bytes、materialized crop、wide-gamut/HDR backend。
