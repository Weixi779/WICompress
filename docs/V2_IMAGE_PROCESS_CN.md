# WICompress 2.0 Image Process

状态：Process Domain、同步 Swift API、执行边界与 1.x Process 删除已落地；异步
terminal 尚未实施。

本文记录 `WIImageProcess` 正向处理产品线已经接受的职责、尺寸插槽、裁切语义、
输出组合与执行边界。1.x 事实和调研证据保留在
[`V2_CAPABILITY_MAP_CN.md`](V2_CAPABILITY_MAP_CN.md)。

内部状态与编排已经由
[`V2_IMAGE_PIPELINE_CN.md`](V2_IMAGE_PIPELINE_CN.md) 重新冻结；本文关于
Resolver、ExecutionPlan 和 Executor 的旧描述仅属于历史迁移背景，这些架构类型已删除。

相关文档：

- [`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md)：跨产品线共享 Domain。
- [`V2_COMPRESSION_TARGET_CN.md`](V2_COMPRESSION_TARGET_CN.md)：反向 byte-budget 求解。
- [`V2_IMAGE_IO_CN.md`](V2_IMAGE_IO_CN.md)：encoded representation 基础设施。
- [`V2_IMAGE_RASTER_CN.md`](V2_IMAGE_RASTER_CN.md)：crop、resize 与颜色绘制基础设施。

## 产品职责

`WIImageProcess` 描述一次由调用方控制的确定性图片处理：

```text
source image
+ optional crop
+ caller-selected resizing
+ caller-selected lossy quality
+ caller-selected output requirements
    -> execute once
    -> encoded Data
```

它不是 byte-budget solver。最终 byte count 是结果，不是成功条件；需要硬字节上限的
调用方使用 `WICompressionTarget`。

Process 是不可变、`Sendable` 的纯描述值，不持有 source、decoded bitmap、Task 或
mutable pipeline。配置过程不执行 inspect、decode、render 或 encode；一次 terminal
call 才开始工作。

## 公共信息分组

Process 的概念分组为：

```text
WIImageProcess
├── sizing
├── optional cropping
├── optional lossy quality
└── output
```

这些分组表达不同所有者和组合关系，不再合并为一个 `Policy`。最终类型名、初始化器标签
和默认参数已经由 Phase 4 同步纵向切片确认。

## Swift API

同步入口保持静态 facade，Process 本身只是一份不可变描述：

```swift
let process = WIImageProcess(
    sizing: .resize(
        using: WIImageResize.constrained(
            within: WIPixelSize(width: 2_048, height: 2_048)
        )
    ),
    crop: WIImageCrop(aspectRatio: .square),
    quality: 0.7,
    output: WIImageOutput(
        representation: .pngIfAlphaOtherwiseJPEG,
        metadata: .strip,
        colorSpace: .convert(to: .sRGB)
    )
)

let result = try WICompressor.process(sourceData, using: process)
```

文件入口使用同一 Process：

```swift
let result = try WICompressor.process(contentsOf: url, using: process)
```

文件 terminal 直接建立 file-backed ImageIO source，不在入口处读取完整 `Data`。
只有 passthrough 需要返回原始 bytes 时，才按需读取文件；decode、thumbnail、copy 和
encode 路径继续由 URL source 驱动。

`WIImageResize` 提供 `.luban`、`.maximumPixelSize(_:)`、
`.constrained(within:allowingUpscaling:)`、`.scaled(by:)` 和 `.exact(_:)`。
调用方也可以直接实现 `WIImageResizing`。这些便利实现不会扩展
`WIImageSizing` 的核心 case。

anchor 与 quality 是可安全规范化的偏好：anchor clamp 到 `0...1`，quality clamp 到
`0...1`；NaN 分别回退到中心和默认 `0.6`。ratio 与 scale 没有可信的自动修复语义，
对应构造使用 typed throws。

## Sizing 与 Resizing 插槽

Sizing 只有两个状态：

```text
original
resize(using: WIImageResizing)
```

`original` 表示不主动改变裁切后图片的像素尺寸。`resize` 接收一个从完整源尺寸到完整目标
尺寸的决策插槽：

```swift
public protocol WIImageResizing: Sendable {
    func targetSize(
        for sourceSize: WIPixelSize
    ) throws(WICompressError) -> WIPixelSize
}
```

协议只接收一个已经考虑 orientation 和可选 crop 的完整 `WIPixelSize`，只返回一个完整
目标 `WIPixelSize`。它不接收 ImageIO source、encoded bytes、quality、format、View
point 或 Target solver context。

算法失败直接抛 `WICompressError.invalidResizing`；不使用 `(0, 0)` 或其他非法尺寸作为
错误哨兵。

调用方因此可以：

- 直接返回业务已经计算好的像素尺寸。
- 使用 WICompress 提供的等比缩小、明确允许放大的等比缩放、exact size 或 Luban 实现。
- 实现自己的 source-size-to-target-size 算法，而不扩展 WICompress 的公共 case。

内置实现是协议的便利值或静态工厂，不升级为 `fit`、`fill`、`fitInside` 等新的核心
Domain。压缩向的内置实现默认只缩小；只有名称和调用显式表达允许放大时，才接受大于输入
的结果。

Execution Core 会验证返回尺寸为正数，并按 Raster 的 64-byte row alignment 规则检查
row bytes 与总 bitmap bytes 的算术溢出。无效尺寸明确失败，不 silent clamp，也不由
Raster 层再次解释。固定内存预算仍属于后续资源策略，不在这一层暗中引入。

## Cropping

Crop 与 resizing 是两个独立决定：

- Crop 决定保留源图的哪一块内容。
- Resizing 决定保留内容最终拥有多少像素。

2.0 首版公开 concrete aspect ratio crop，不公开九宫格方位枚举、任意 canvas placement
或 UI content mode。Crop 使用归一化锚点：

```swift
public struct WICropAnchor: Sendable, Hashable {
    public let x: Double
    public let y: Double

    public static let center = Self(x: 0.5, y: 0.5)
}
```

公开坐标使用经过 orientation 解释后的图片坐标：

```text
(0, 0) -------- (1, 0)
  |                |
  |    (0.5,0.5)   |
  |                |
(0, 1) -------- (1, 1)
```

- `x` 从左到右。
- `y` 从上到下。
- 默认锚点是 `(0.5, 0.5)`。
- 两个分量必须位于闭区间 `0...1`；越界明确失败，不静默 clamp。

归一化锚点替代 1.x 的中心、四边和四角枚举。它只表达裁切偏向，不表达页面位置或 View
alignment。

### Crop 尺寸

设 oriented source 为 `W × H`，目标宽高比为 `r`：

```text
W / H > r:
    cropHeight = H
    cropWidth  = H × r
    cropX      = (W - cropWidth) × anchor.x

W / H < r:
    cropWidth  = W
    cropHeight = W / r
    cropY      = (H - cropHeight) × anchor.y
```

比例相同时使用完整源图。像素取整只在内部 geometry resolver 中执行一次，并保证 crop
rect 位于源图范围内。

### 固定顺序

语义顺序已经冻结：

```text
oriented source pixel size
    -> resolve aspect-ratio crop and anchor
    -> cropped pixel size
    -> WIImageResizing.targetSize(for: croppedPixelSize)
    -> concrete raster plan
```

因此 resizing 不需要理解 crop，crop 也不需要理解 Luban 或业务尺寸算法。底层可以把
crop 与 resize 融合成一次绘制；语义顺序不要求生成中间 `CGImage`。

## Quality 与 Output

Process 的 lossy quality 由调用方固定，不能由库搜索。PNG 等无损 representation 忽略
有损 quality；JPEG、HEIC 等有损目标按 ImageIO 能力写入。

Process 与 Target 共享 Output Domain：

```text
Output
├── representation
├── metadata
└── color space
```

Quality 不属于 Output，因为 Target 中的 quality 由 solver 所有。Output 的完整合同和
两条产品线的默认值见 [`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md)。

Metadata 是 `WIImageMetadataOptions` 集合，不是互斥 policy。`.strip` 与 `.preserve`
分别是空集合和完整集合；调用方可以直接保留全部类别并排除 location：

```swift
metadata: .preserve.subtracting(.gps)
```

类别选择由 ImageIO encode/source-copy 边界执行，不进入 Raster Domain。

通用 canvas/background 不进入 Process。只有 representation 明确要求 Alpha flatten
时，opaque background 才作为该输出语义的一部分进入最终 raster plan。

## Passthrough 与结果

Process 与 Target 统一返回 `WIResult`。它只承载执行已经产生的 `data`、`format`、
`pixelSize` 和 `byteCount`，不引入新的处理策略或生命周期。`WIResult` 没有 public
initializer，只由 terminal 产出；只需要编码数据时读取 `result.data`。

只有源数据已经满足全部声明且没有任何必须重写的决定时才允许 passthrough，包括：

- 没有 crop。
- sizing 解析后尺寸不变。
- representation、metadata 和 color space 已满足。
- 没有要求重新编码的固定 lossy quality。

如果声明了 crop、颜色转换、metadata strip、Alpha flatten、明确目标容器或固定有损
quality，执行层不能用“原图更小”绕过该合同。

## 同步与异步

同步与异步 terminal 使用同一 Domain、`ImagePipeline`、Raster 和 ImageIO
primitive：

```text
sync terminal  -> 在当前调用上下文完整执行
async terminal -> 在非 caller-actor 的执行上下文完成相同工作
```

配置本身没有 async 版本。inspect、crop、resize 和 encode 也不分别成为 public
suspension point。

当前同步 base name 已确认为 `WICompressor.process(_:using:)` 与
`WICompressor.process(contentsOf:using:)`。异步 overload 尚未加入；它必须消费同一个
`ImagePipeline` 同步核心，不能建立第二套决策路径或改变执行语义。

## 当前实施状态

- 已实现 public `WIPixelSize`、`WIImageResizing`、内置 `WIImageResize`、
  `WIImageSizing`、aspect-ratio crop/anchor、`WIImageOutput` 和
  `WIImageProcess`。
- 已实现纯 `crop -> resizing` geometry calculation；quality 在 Domain 中归一化，
  ratio 构造和 resizing 执行失败直接抛 Domain error。
- 已实现同步 Data/file terminal；Process 的 output 解释、执行分支选择和结果生成由
  请求级 `ImagePipeline` 直接持有，不经过 `WIExecutionPlan`、旧
  `WICompressOptions` 或 Resolver。
- 无 crop 的缩小复用 ImageIO thumbnail；thumbnail max pixel 由目标宽、高两个轴
  共同反推，不能先把任一目标轴所需的源样本降掉再放大。需要放大任一轴时使用完整
  source。crop 使用完整 oriented source，并在 Raster 中把
  crop/resize/color/background 融合成一次绘制。
- file terminal 保持 file-backed source；只有 return-original passthrough 才按需
  读取完整原始 `Data`。
- 1.x `compress(_:options:)`、旧 Policy 名称和 legacy write-plan resolver
  已删除；2.0 不维护第二套 Process 架构。
- `WICompressionTarget` 已共享 `WIImageOutput`；两条产品线共用同一个
  `ImagePipeline` 和底层执行能力。Target 构造时建立 hard byte invariant；passthrough、
  反馈搜索和 hard byte check 位于 Pipeline；架构级 Plan/Resolver/Solver 已删除。
- 尚未实现 async terminal。

## 已接受

- Process 与 Target 是两条产品线，由同一个 internal `ImagePipeline` 编排。
- Process 返回 `WIResult`，执行一次，不以 byte count 作为反向求解目标。
- Sizing 只有 original 或一个 `WIImageResizing` 插槽。
- `WIImageResizing` 的合同是完整 `PixelSize -> PixelSize`。
- WICompress 可以提供内置 resizing 实现，但不为每个算法扩展核心 enum。
- Crop 与 resizing 分开，crop 先解析，resizing 接收裁后尺寸。
- Aspect-ratio crop 使用连续 normalized anchor，默认居中。
- 不使用九宫格 crop/alignment enum。
- Crop、resize、orientation、background 和 color render 在底层融合成一次绘制。
- Process quality 由调用方固定，Output 与 Target 共用。
- 同步与异步入口共享同一执行核心。

## 已拒绝

- 把所有字段重新装进一个 Process Policy。
- Public processor chain、开放节点 Pipeline 或 processor registry。
- 让每一步返回或持有 public ImageResource。
- 使用 `fit`、`fill`、`fitInside` 或 View content mode 作为核心术语。
- 让 Execution Core 接收单独长边、Luban ratio 或业务 intent。
- 让 Raster 层重新决定 crop、resizing、output 或 quality。
- 为 crop 公开中心、四边和四角枚举。
- 通过 warning、silent clamp 或隐式 format fallback 掩盖无效合同。

## 延后

- 任意 source pixel rect crop。
- Content-aware、face、entropy 等自动裁切算法。
- 通用 canvas placement、stretch 和非压缩绘图能力。
- Public source descriptor 或长期 ImageResource。
- 结构化 Process result 与执行 diagnostics。
- Callback 便利入口。

这些能力只有出现真实消费者或失败证据时重新打开；2.0 不为了 API 完整性提前建立协议。
