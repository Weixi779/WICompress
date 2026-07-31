# WIImageDomain 数据领域

状态：已实现。`WIImageDomain` 是 WICompress 2.0 的基础 target，不声明独立
library product；调用方仍然只需 `import WICompress`。

## 为什么需要 Domain

旧结构同时存在公开的 `WIPixelSize`、`WIColorSpace`、`WIColor`、`WIImageFormat`
与 package-only 的 `PixelSize`、`ColorSpace`、`Color`、`ImageFormat`。这些类型描述
同一事实，却迫使 Source、Resolver、Raster 和 Encoder 不断转换。

2.0 不再用访问级别制造平行模型。公开值可以直接被 package 内部执行层使用，执行所需
的校验和平台转换通过 package 方法补充。

依赖方向固定为：

```text
                 WIImageDomain
                   ↑       ↑
           WIImageIO       WIImageRaster
                   ↑       ↑
               WICompressExecution
                       ↑
                   WICompress
```

`WICompress` 通过 umbrella export 保持单一 import；target 边界只约束包内依赖方向。

## Domain 所有权

`WIImageDomain` 拥有调用方输入和执行层共同理解的值：

- `WIPixelSize`
- `WIColor` / `WIColorSpace`
- `WIImageProcess` / `WIImageSizing`
- `WIImageResizing` / `WIImageResize`
- `WIImageCrop` / `WIAspectRatio` / `WICropAnchor`
- `WIImageOutput` / representation / metadata / color-space decisions
- `WICompressionTarget` / `WICompressionSizing`

它还拥有 package-only 的 `Rect`、`Orientation` 和尺寸执行校验。Luban 纯尺寸算法留在
Domain 内，作为 `WIImageResize.luban` 的实现细节。

## 不属于 Domain 的事实

- `WIImageFormat` 由 `WIImageIO` inspection 产生。它是公开结果事实，但没有公开的
  Data detection API 或自定义 initializer；内部精确容器统一使用 `UTType`。
- `WIImageMetadataOptions` 属于共享 Output Domain；ImageIO Descriptor 直接使用它
  表达源图实际存在的受支持 metadata 类别。
- `Source`、Descriptor、thumbnail、encode 和 runtime capability 属于 `WIImageIO`。
- bitmap context、orientation render、Alpha surface 和颜色转换属于
  `WIImageRaster`。
- Resolver、Execution Plan、Executor、Target Solver 和公开结果
  `WIResult` 属于 `WICompressExecution`。
- `WICompressor` 属于公开 umbrella `WICompress`。

## WIPixelSize 合同

`WIPixelSize` 是唯一的像素尺寸类型。公开 initializer 接受调用方意图；ImageIO、
Resolver 和 Raster 在进入执行边界时调用 package 校验，保证：

- width 与 height 均为正数；
- `width * height` 不发生整数溢出。

非法自定义 resizing 结果仍映射为 `WICompressError.invalidResizingResult`。这里不再
引入一个“已验证 PixelSize”影子类型；验证状态属于执行流程，不构成第二个数据领域。

## 迁移结果

- 删除 `WIImageCore` target。
- 删除 `PixelSize`、`ColorSpace`、`Color` 和 `ImageFormat` 影子类型。
- 删除 `imageCoreValue` 等逐字段适配。
- 删除 `WISize`，结构化压缩结果直接使用 `WIPixelSize`。
- 删除 Execution 对 ImageIO Descriptor 和公开 Result 的逐字段影子值。
- ImageIO、Raster 与 Execution 直接消费同一套 Domain 值。
