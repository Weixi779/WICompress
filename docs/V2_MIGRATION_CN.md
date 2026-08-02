# WICompress 2.0 迁移指南

状态：随 2.0 实施持续更新。

WICompress 2.0 是一次有意的 breaking release。需要继续使用 1.x API 或 Swift 6.2
之前工具链的项目，应继续依赖 1.x。

## Package 与入口名称

Package、library product、module 和 import 名称保持不变：

```swift
import WICompress
```

公共静态 terminal 从 `WICompress` 重命名为 `WICompressor`。1.x 到 2.0 的入口
对应关系如下：

| 1.x | 2.0 |
|---|---|
| `WICompress.compress(_:options:)` | `WICompressor.process(_:using:)` |
| `WICompress.compress(contentsOf:options:)` | `WICompressor.process(contentsOf:using:)` |
| `WICompress.compress(_:to:)` | `WICompressor.compress(_:to:)` |
| `WICompress.compress(contentsOf:to:)` | `WICompressor.compress(contentsOf:to:)` |

`options` 到 `process` 是 Domain 迁移，不是只有 base name 不同的源码兼容 overload。
若代码曾跟随未发布的 2.0 草案使用 `WICompress.process`，只需把 facade 改为
`WICompressor.process`。

2.0 的默认 Process 尺寸算法升级为 `WIImageResize.lubanV2`。它会比 Luban 1
更完整地保留普通长截图，并限制超长图和超大像素输入。需要延续 WICompress 修正版
Luban 1 尺寸结果时，应显式传入 `.resize(using: WIImageResize.luban)`；两个版本都不会
隐式改变 Process 的 quality 或输出格式。

例如：

```swift
import WICompress

let result = try WICompressor.process(
    input,
    using: WIImageProcess()
)
```

`WICompressor` 是只有静态方法、不能实例化的 namespace。2.0 不提供旧类型 alias、
deprecated wrapper 或 `.shared` 单例；这能避免 package/module 名和执行入口继续使用
同一个 `WICompress` 标识符。

对于已经采用 2.0 Process/Target Domain 的代码，本次 facade 重命名不改变同步方法的
参数标签、typed error 或执行语义。Process 与 Target 现在统一返回 `WIResult`；
原先直接使用 Process `Data` 的位置改为读取 `result.data`。

2.0 同时为四个 Data/file Process/Target terminal 提供同名 async overload：

```swift
let result = try await WICompressor.process(input, using: process)
let thumbnail = try await WICompressor.compress(input, to: target)
```

同步 overload 继续使用 typed `throws(WICompressError)`，并在当前调用上下文完整执行。
异步 overload 使用普通 `async throws`：图片处理失败仍是 `WICompressError`，Task 取消则
原样抛出 `CancellationError`。取消只在 Pipeline 阶段边界与 Target 搜索尝试之间观察，
不会强行中断已经进入 ImageIO 或 Core Graphics 的单次调用。

## Domain 迁移

2.0 删除 1.x 的 Options/Policy terminal，不维护第二套兼容架构：

- 确定一次 resize、crop、quality 和 output 时，使用 `WIImageProcess` 与
  `WICompressor.process`。
- 要求最终结果不超过明确的 `maxBytes` 时，使用 `WICompressionTarget` 与
  `WICompressor.compress`。

完整的 2.0 Domain 边界见
[`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md)，两条产品线合同分别见
[`V2_IMAGE_PROCESS_CN.md`](V2_IMAGE_PROCESS_CN.md) 与
[`V2_COMPRESSION_TARGET_CN.md`](V2_COMPRESSION_TARGET_CN.md)。
