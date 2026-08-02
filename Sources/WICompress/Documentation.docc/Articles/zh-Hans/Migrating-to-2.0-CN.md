# 迁移到 WICompress 2.0

从 1.x Options 与 Policy API 迁移到 Process 与 Target Domain。

WICompress 2.0 是一次有意的 breaking release，并要求 Swift 6.2 工具链。如果项目仍需
使用旧 API 或旧工具链，应继续依赖 1.x。

## Package 与 import 保持不变

Package、library product、module 和 import 名称没有变化：

```swift
import WICompress
```

公共 terminal namespace 改为 ``WICompressor``。2.0 不提供 `.shared` 单例、deprecated
wrapper 或旧类型 alias。

| 1.x | 2.0 |
| --- | --- |
| `WICompress.compress(_:options:)` | `WICompressor.process(_:using:)` |
| `WICompress.compress(contentsOf:options:)` | `WICompressor.process(contentsOf:using:)` |
| `WICompress.compress(_:to:)` | `WICompressor.compress(_:to:)` |
| `WICompress.compress(contentsOf:to:)` | `WICompressor.compress(contentsOf:to:)` |

## 替换 Options 与 Policy

当应用明确指定 resize、crop、quality 与 output 时使用 ``WIImageProcess``；当最终结果
必须满足硬性 `maxBytes` 时使用 ``WICompressionTarget``。

```swift
let result = try WICompressor.process(input, using: process)
let constrained = try WICompressor.compress(input, to: target)
```

两条路径现在统一返回 ``WIResult``。以前直接使用 Process `Data` 的代码应改为读取
`result.data`。

## 检查默认尺寸算法变化

默认 Process 现在使用 ``WIImageResize/lubanV2``。如果需要延续 WICompress 修正版
Luban 1 的尺寸结果，应显式选择：

```swift
let process = WIImageProcess(
    sizing: .resize(using: WIImageResize.luban)
)
```

两种 Luban 实现都不会独立改变输出格式或 quality。

## 迁移同名 async overload

Data 与文件 Process/Target terminal 都增加了 async overload：

```swift
let result = try await WICompressor.process(input, using: process)
```

Swift 在 async 上下文中会优先选择 async overload。升级后，async function 中原有的
同步调用必须增加 `await`，不会继续自动选择同步 overload。如果确实需要同步
执行，应在非 async helper 中调用，或显式绑定同步函数 overload。

同步 overload 保留 typed `throws(WICompressError)`。异步 overload 还会原样抛出
`CancellationError`，详见 <doc:Concurrency-and-Cancellation-CN>。
