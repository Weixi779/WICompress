# WICompress 2.0 Image Raster Core

状态：模块职责、单次绘制合同和首版非目标已冻结；具体实现等待 Execution Plan 定型。

本文记录 WICompress 2.0 对 Core Graphics 像素绘制能力的内部二次封装。它位于 ImageIO
decode 与 encode 之间，只执行已经解析完成的几何和输出决定，不定义
`WIImageProcess`、`WICompressionTarget` 或 UI 展示语义。

相关文档：

- [`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md)：跨产品线 Domain 与执行边界。
- [`V2_IMAGE_PROCESS_CN.md`](V2_IMAGE_PROCESS_CN.md)：crop 与 resizing 的公共合同。
- [`V2_COMPRESSION_TARGET_CN.md`](V2_COMPRESSION_TARGET_CN.md)：Target 固定裁切与
  solver 边界。
- [`V2_IMAGE_IO_CN.md`](V2_IMAGE_IO_CN.md)：inspect、decode、encode 与 source copy。

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

新增独立、非 product 的 package target，本文概念上称为 `WIImageRaster`：

```text
WIImageIO ── decode ──┐
                     ▼
                 WIImageRaster
                     │
                     └── image
                           │
                           ▼
WIImageIO ── encode ◀── CGImage
```

首版约束：

- target 不声明独立 library product。
- 跨 target 只暴露一个 package-level 图片绘制入口。
- 不依赖 Process、Target、solver、Luban、UIKit 或 AppKit。
- primitive 保持同步，不拥有 queue、actor、Task 或 cancellation。
- target 名称和共享 pixel value 的最终归属在 SwiftPM 实施设计中确认，但职责边界不再
  重新讨论。

## 唯一模块入口

调用层只看见一个 terminal pixel operation，概念 API 为：

```swift
let image = try ImageRaster.image(
    decodedImage,
    sourceRect: resolvedCropRect,
    pixelSize: resolvedOutputSize,
    background: resolvedBackground,
    colorSpace: resolvedColorSpace
)
```

最终参数可以收敛到 immutable raster plan，但该 plan 只能包含已经解析完成的事实：

```text
oriented source image
source pixel rect
destination pixel size
resolved background
resolved output color space
```

它不包含：

- `fit`、`fill`、`fitInside` 或 content mode。
- aspect ratio、anchor、Luban 或 `WIImageResizing`。
- `maxBytes`、quality search、candidate ranking 或 retry。
- representation、metadata 或编码格式选择。

Raster 不再解释 Domain。上层 resolver 负责把 crop、resizing 和 Output 转换为 concrete
plan，Raster 只执行。

## Bitmap Surface 是隐藏实现

内部可以有一个管理 bitmap surface 的低层 primitive，概念名称为 `BitmapSurface`：

```swift
private enum BitmapSurface {
    static func image(
        pixelSize: RasterPixelSize,
        background: RasterBackground,
        colorSpace: RasterColorSpace,
        draw: (CGContext) throws -> Void
    ) throws -> CGImage
}
```

它拥有：

- checked row-byte 与 total-byte 计算。
- canonical standard-range bitmap format。
- row alignment 和 buffer allocation。
- top-left user-space CTM。
- transparent clear 或 opaque background fill。
- scoped `CGContext` 生命周期。
- 一次性 snapshot/finalize。

`BitmapSurface` 首版保持 target-private。它只有 `ImageRaster` 一个真实消费者，不升级为
第二套 package API，也不向外暴露 raw pointer、bitmap info 或任意 CGContext builder。

## 坐标与 Orientation

Raster 接收的 `sourceRect` 使用 oriented image pixel coordinates：

- 原点在左上。
- x 向右增加。
- y 向下增加。
- rect 必须落在 oriented source 的有效像素范围内。

Raster 内部统一处理原始 `CGImage` pixel storage、EXIF orientation 和 Core Graphics
坐标系。输出总是：

```text
orientation = up
pixel size = resolved destination size
coordinate meaning = top-left image coordinates
```

调用层不直接对未 bake orientation 的 `CGImage` 使用视觉 crop rect，也不接触
`flip: Bool` 之类同时混合多个坐标概念的开关。

## Crop 与 Resize 只绘制一次

Raster 不先创建 crop image 再 resize。它创建最终目标大小的 bitmap surface，计算 source
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

Raster 接收的是 Output resolver 已经完成的结果，不拥有第二套公开 Policy。

内部 background 只有两个互斥状态：

```text
transparent
solid(opaque color)
```

- transparent 使用带 premultiplied Alpha 的 surface，并保证初始像素清零。
- solid 使用 opaque surface，先完整填充画布，再绘制 source。
- JPEG Alpha flatten 只有在 Output 已显式选择 opaque background 时进入 solid。

首版 surface 使用 standard-range、8-bit canonical RGB layout。sRGB 是压缩输出的稳定
基线；preserve、Display P3 或 custom ICC 是否可兑现由 Output resolver 和 ImageIO
capability 共同决定，再传入 Raster。HDR、EDR 和 tone mapping 不伪装成普通 color 或
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

Raster primitive 同步执行，并只在一次 terminal 调用的当前执行上下文中存在：

```text
sync WICompress  -> 当前调用上下文调用 Raster
async WICompress -> 工作任务调用同一个 Raster
```

不同顶层调用可以并发创建各自 surface；同一个 context 不跨线程、Task 或 actor 共享。
Raster target 不建立全局串行队列。

## 与完整执行链的关系

```text
WIImageProcess ────────┐
                       ├── resolver / solver
WICompressionTarget ───┘
                              │
                              ▼
                    concrete execution plan
                              │
                              ▼
                       WIImageIO source
                         │           │
                 image/thumbnail     └── source copy passthrough
                         │
                         ▼
                    ImageRaster.image
                         │
                         ▼
                    WIImageIO encode
                         │
                         ▼
                        Data
```

ImageIO 的美感来自 inspect、image、thumbnail、encode 等离散 representation 能力；
Raster 的美感来自把有状态的 Core Graphics machinery 压缩成一次准确的 `image` 操作。
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

## 验证合同

独立模块至少覆盖：

- 八种 EXIF orientation 输入都输出 `.up` 且视觉尺寸正确。
- normalized top-left crop rect 映射到正确像素区域。
- crop + resize 只产生最终大小的 destination surface。
- transparent 与 solid background 的 Alpha 结果。
- JPEG flatten 所需 opaque background 可以完整覆盖画布。
- sRGB standard-range surface 的 pixel format 和编码兼容性。
- 非正尺寸、越界 rect、row-byte/total-byte overflow 和 context creation failure。
- `bytesPerRow × height` 成本估算使用实际 row padding。
- sync 与 async terminal 对同一 plan 得到一致 raster 结果。

## 已冻结与延后

已冻结：

- 独立、非 product 的 Raster target。
- package 调用层只有 `ImageRaster.image` 一个入口。
- `BitmapSurface` target-private。
- Raster 只消费 resolved geometry/output，不解释 Domain。
- top-left oriented pixel coordinates，输出 orientation 恒为 `.up`。
- crop + resize + orientation + background + color 单次绘制。
- pixel-only、同步 primitive、无全局队列。

延后：

- target 和类型的最终 Swift 拼写。
- shared pixel value 在 target graph 中的具体归属。
- 内部 interpolation 的 benchmark 结果。
- raw mutable bytes、materialized crop、wide-gamut/HDR backend。
