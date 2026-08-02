# WIImageIO 快速开始

打开一次编码图片，读取稳定事实，并选择能够满足要求的最轻操作。

## 添加 Product

将 `https://github.com/Weixi779/WICompress.git` 添加为 Swift Package 依赖，
并为应用 Target 链接 `WIImageIO` product。

```swift
import UniformTypeIdentifiers
import WIImageIO
```

## 打开 Data 或文件

``ImageReader`` 接受编码 Data 和文件 URL：

```swift
let dataReader = try ImageReader(imageData)
let fileReader = try ImageReader(contentsOf: fileURL)
```

文件 Reader 会把 URL 直接交给 ImageIO，不会先把整个文件 materialize 成 `Data`。
ImageIO 在 inspection 或后续处理中仍可能读取任意乃至全部文件内容。Reader 会在
初始化时检查输入，并缓存一个 ``ImageDescriptor``。

如果只需要源图事实，可以使用静态 inspection：

```swift
let descriptor = try ImageReader.inspect(imageData)
let fileDescriptor = try ImageReader.inspect(contentsOf: fileURL)
```

Descriptor 包含编码类型与格式、字节数、存储与展示像素尺寸、方向、帧数、Alpha、
已建模 metadata 类别和 gain map。`hasAlpha` 是 optional，因为部分容器在属性检查阶段
无法给出可靠结论。

## 解码缩略图

不需要完整分辨率像素时，应优先使用 thumbnail：

```swift
let frame = try dataReader.thumbnail(
    options: ImageThumbnailOptions(maximumPixelSize: 1_280)
)
```

Thumbnail 默认应用展示方向，因此返回 `.up` orientation。相比之下，
``ImageReader/image(options:)`` 解码存储帧，并保留明确的 orientation。

## 编码 Frame

```swift
let output = try frame.encode(
    as: .jpeg,
    options: ImageEncodeOptions(
        compressionQuality: 0.72,
        metadata: .strip
    )
)
```

Reader 创建的 ImageFrame 会携带可用 metadata provenance 的快照。由调用方
`CGImage` 创建的 Frame 没有可以继续保留的源 metadata。

如何选择 decode、transcode 与 encode，见 <doc:ImageIO-Operations-CN>。
