# WIImageDomain 与 WICompressDomain

状态：已实现。`WIImageDomain` 是共享图片事实的基础 target，`WICompressDomain`
拥有压缩请求语义；两者不声明独立 library product。压缩调用方只需
`import WICompress`，需要底层编解码能力的调用方可以单独 `import WIImageIO`。

## 为什么需要 Domain

旧结构同时存在公开的 `WIPixelSize`、`WIColorSpace`、`WIColor`、`ImageFormat`
与 package-only 的 `PixelSize`、`ColorSpace`、`Color`、`ImageFormat`。这些类型描述
同一事实，却迫使 Source、Resolver、Rendering 和 Encoder 不断转换。

2.0 不再用访问级别制造平行模型。公开值可以直接被 package 内部执行层使用，执行所需
的校验和平台转换通过 package 方法补充。

依赖方向固定为：

```text
                    WIImageDomain
                  ↑       ↑       ↑
         WIImageIO  WIImageRendering  WICompressDomain
                  ↖      ↑      ↗
                WICompressExecution
                         ↑
                     WICompress
```

`WICompress` 通过 umbrella export 保持单一 import；target 边界只约束包内依赖方向。

## Domain 所有权

`WIImageDomain` 拥有 ImageIO、Rendering、压缩请求与执行层共同理解的图片事实：

- `WIPixelSize`
- `WIColor` / `WIColorSpace`
- `ImageMetadataOptions`
- `ImageFormat`
- `WIImageOrientation`
- package-only `Rect`

`WICompressDomain` 拥有调用方描述压缩意图的值：

- `WIImageProcess` / `WIImageSizing`
- `WIImageResizing` / `WIImageResize`
- `WIImageCrop` / `WIAspectRatio` / `WICropAnchor`
- `WIImageOutput` / representation / metadata / color-space decisions
- `WICompressionTarget` / `WICompressionSizing`
- `WICompressError`

Luban 1/2 纯尺寸算法与数值规范化留在 `WICompressDomain`，作为请求构造和
`WIImageResize.luban` / `.lubanV2` 的实现细节。两个版本都不拥有 quality、
目标字节或编码格式。

## 不属于 Domain 的事实

- 从 encoded data 读取 `UTType` 属于 `WIImageIO`；将 `UTType` 映射为稳定容器家族
  属于 `ImageFormat`，由 Domain 统一表达。
- `ImageMetadataOptions` 属于共享 Output Domain；ImageIO ImageDescriptor 直接使用它
  表达源图实际存在的受支持 metadata 类别。
- `ImageReader`、ImageDescriptor、ImageFrame、thumbnail、encode 和 runtime capability 属于
  `WIImageIO`；该 target 同时发布独立 product。
- bitmap context、orientation render、Alpha surface 和颜色转换属于
  `WIImageRendering`。
- `WIResult` 属于 `WICompressDomain`，是 Process 与 Target 共同的公开成功合同。
- 请求级 `ImagePipeline` 与 Target 反馈搜索属于 `WICompressExecution`；Execution 不拥有
  public product model。
- `WICompressor` 属于公开 umbrella `WICompress`。

## WIPixelSize 合同

`WIPixelSize` 是唯一的像素尺寸类型。公开 initializer 将非正 width/height 归一到一个
像素，避免常用尺寸 API 被 throwing construction 污染。ImageIO inspection 不使用这项
容错：它先严格拒绝非正尺寸与 pixel-count overflow，再建立可信的 Source fact。

`WICompressDomain` 中的 `WIImageResizing.targetSize(for:)` 使用
`throws(WICompressError)`；自定义算法失败直接抛
`.invalidResizing`，不再通过 `(0, 0)` 哨兵值把错误延迟到 Pipeline。Rendering 执行前仍会
拒绝 row-byte 或 bitmap-byte overflow；这里不引入“已验证 PixelSize”影子类型。

可以确定最近合法含义的偏好直接规范化：anchor clamp 到 `0...1`，quality clamp 到
`0...1`，NaN 分别回退到中心和默认 quality。无法可靠推断意图的 ratio、scale 与
Target hard byte contract 在构造时直接抛 `WICompressError`。

## 迁移结果

- 删除 `WIImageCore` target。
- 删除 `PixelSize`、`ColorSpace`、`Color` 和 `ImageFormat` 影子类型。
- 删除 `imageCoreValue` 等逐字段适配。
- 删除 `WISize`，结构化压缩结果直接使用 `WIPixelSize`。
- 删除 Execution 对 ImageIO ImageDescriptor 和公开 Result 的逐字段影子值。
- ImageIO、Rendering、Compress Domain 与 Execution 直接消费同一套共享图片事实。
- Process、Target、Output、Crop、Resizing 与 Luban 从共享图片事实中拆到
  `WICompressDomain`，避免独立 ImageIO product 携带整套压缩请求语义。
- `WICompressError` 归属 `WICompressDomain`；独立产品的底层失败由
  `ImageIOError` 表达，并在 Pipeline 边界映射。
