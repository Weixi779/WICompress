# Process 与 Target

在确定性图片操作与具有硬字节上限的反馈搜索之间选择。

## 定义 Process

``WIImageProcess`` 将一次图片操作分成四组事实：

- `crop` 可选出一个宽高比区域。
- `sizing` 根据裁切后的像素尺寸得出目标尺寸。
- `quality` 提供有损编码质量；`nil` 表示不主动指定。
- `output` 定义格式、metadata 与色彩空间要求。

```swift
let process = WIImageProcess(
    sizing: .resize(using: WIImageResize.maximumPixelSize(1_600)),
    quality: 0.72,
    output: WIImageOutput(
        representation: .pngIfAlphaOtherwiseJPEG,
        metadata: .strip,
        colorSpace: .preserve
    )
)

let result = try await WICompressor.process(input, using: process)
```

裁切始终发生在 resize 之前。Anchor 使用左上角为原点的 `0...1` 归一化坐标，
超出范围的值会被截入区间。

```swift
let crop = try WIImageCrop.aspectRatio(
    width: 4,
    height: 3,
    anchor: WICropAnchor(x: 0.5, y: 0.25)
)

let result = try await WICompressor.process(
    input,
    using: WIImageProcess(crop: crop)
)
```

内置尺寸算法包括 Luban V2、修正版 Luban 1、最长边限制、二维等比约束、明确比例
与精确尺寸。自定义实现只需要遵守 ``WIImageResizing``，根据一个完整源图尺寸返回
一个完整目标尺寸。

## 定义 Target

``WICompressionTarget`` 面向上传或分享 SDK 这类硬性限制。WICompress 会搜索候选质量
与尺寸，并在结束前再次验证结果没有超过 `maxBytes`。
默认 Target 对含 Alpha 源图使用 PNG，否则使用 JPEG；同时移除非展示 metadata，
并将渲染像素转换为 sRGB。

```swift
let target = try WICompressionTarget(
    maxBytes: 500_000,
    sizing: WICompressionSizing(maximumPixelSize: 1_600)
)

let result = try await WICompressor.compress(input, to: target)
```

可选宽高比会在搜索前增加一次明确裁切：

```swift
let square = try WIAspectRatio(width: 1, height: 1)
let target = try WICompressionTarget(
    maxBytes: 250_000,
    sizing: WICompressionSizing(
        maximumPixelSize: 1_080,
        aspectRatio: square,
        anchor: .center
    )
)
```

Target 不接受调用方指定的 quality。Quality 与后续降尺寸都是压缩器拥有的搜索变量。
如果当前支持的输出路径无法满足硬上限，操作会抛出
``WICompressError/targetUnsatisfiable(smallestByteCount:)``。

## 共用 Output

Process 与 Target 使用同一个 ``WIImageOutput``，因此格式、metadata 和色彩空间要求
在两条路径上具有完全相同的含义。

内部搜索与 Pipeline 设计见
[架构文档](https://github.com/Weixi779/WICompress/blob/main/docs/architecture/README_CN.md)。
