# WICompress 快速开始

把 WICompress 添加到应用中，并使用默认 Process 完成一次图片处理。

## 添加 Package

将 `https://github.com/Weixi779/WICompress.git` 添加为 Swift Package 依赖，
并为应用 Target 链接 `WICompress` product。

```swift
import WICompress
```

WICompress 2.0 要求 Swift 6.2 工具链。暂时不能升级工具链的项目应继续使用
WICompress 1.x。

## 处理编码数据

最短调用使用 ``WIImageProcess/default``。默认 Process 使用 Luban V2 尺寸算法、
`0.6` 有损质量、移除非展示 metadata，并在可能时保留源图格式和正常显示色彩语义。

```swift
let result = try await WICompressor.process(originalData)

let encodedData = result.data
let format = result.format
let pixelSize = result.pixelSize
let byteCount = result.byteCount
```

``WIResult`` 是 Process 与 Target 共同的结果类型。只有到 UI 边界时，才需要把
`result.data` 解码成平台图片。

## 处理文件

使用文件 URL 可以让 ImageIO 直接打开编码源：

```swift
let result = try await WICompressor.process(contentsOf: fileURL)
```

Data 与文件入口具有相同的图片语义。文件入口会把 URL 直接交给 ImageIO，不会先
建立完整 `Data` 副本；ImageIO 执行操作时仍可能读取任意乃至全部文件内容。只有
original passthrough 需要返回编码字节时，才会另外 materialize `Data`。

## 选择入口

- 已经明确 resize、crop、quality 和 output 时，使用
  `WICompressor.process(_:using:)`。
- 最终编码结果必须小于明确字节上限时，使用
  `WICompressor.compress(_:to:)`。

两条 Domain 的区别见 <doc:Process-and-Target-CN>，执行行为见
<doc:Concurrency-and-Cancellation-CN>。
