# WIImageCore 内部基础模型

状态：已实现。`WIImageCore` 是 WICompress 2.0 的 package-only 基础 target，
不声明独立 library product，也不扩大公共 API。

## 为什么需要 Core

ImageIO、Raster 和产品 Pipeline 原本分别定义尺寸、矩形、方向、格式、颜色与色彩空间。
这些类型描述的是同一组底层图像事实，却需要在 `WIImageSource` 和
`WIImageEncoder` 中逐字段转换。重复定义不仅增加代码量，也让方向、颜色空间和尺寸
合法性的合同分散在不同模块。

`WIImageCore` 只收口存在多个真实消费者的基础值：

```text
WIImageCore
  ├── PixelSize
  ├── Rect
  ├── Orientation
  ├── ImageFormat
  ├── ColorSpace
  └── Color
```

依赖方向固定为：

```text
             WIImageCore
              ↑       ↑
      WIImageIO       WIImageRaster
              ↑       ↑
                 WICompress
```

## 类型合同

| 类型 | 合同 |
| --- | --- |
| `PixelSize` | 宽高必须为正，且 `width * height` 不溢出 |
| `Rect` | 使用左上角原点的像素坐标；具体边界由消费者验证 |
| `Orientation` | 完整表达 EXIF 1...8，并统一判断是否交换显示轴 |
| `ImageFormat` | 只表达 JPEG、PNG、HEIF 和 unknown 容器事实 |
| `ColorSpace` | 只表达具体 RGB 色彩空间，不包含 preserve/source 策略 |
| `Color` | 表达带具体色彩空间的 RGBA 值 |

`PixelSize` 是合法执行事实。公开的 `WIPixelSize` 仍然是调用方意图，可以暂时包含
非法值；Resolver 在建立执行计划时完成验证，并继续映射为
`WICompressError.invalidResizingResult`。因此 Core 提取不改变自定义
`WIImageResizing` 的公开错误合同。

## 所有权边界

`WIImageCore` 不拥有：

- ImageIO source、decode、thumbnail、encode 或 runtime capability。
- Raster plan、Alpha surface、source color preserve 或 bitmap memory policy。
- Process、Target、Luban、crop intent、quality search 或 byte solver。
- 公开 Domain、异步调度、缓存、网络和 UI 类型。

容器检测仍由 `WIImageIO` 扩展 `ImageFormat` 完成；`.source` 仍是
`WIImageRaster.OutputColorSpace` 的执行决定，而不是 `ColorSpace` case。

## 迁移结果

- `WIImageIO.Source` 的 `Descriptor` 直接持有 Core format、size 和 orientation。
- `WIImageRaster.Plan` 直接消费 Core size、rect、orientation 和 color。
- `WIExecutionPlan` 只持有已经验证的 Core 执行事实。
- `WIImageEncoder` 不再逐字段复制尺寸、矩形、方向、颜色或色彩空间。
- 公开的 `WIImageFormat`、`WIPixelSize`、`WIColorSpace` 和 `WIColor` 保持不变，
  只在产品边界转换一次。

`WICompress` 到 `WICompressor` 的公开入口重命名、async API、Solver 重写和
Encoder 进一步拆分不属于本阶段。
