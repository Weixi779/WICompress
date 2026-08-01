# WIImageIO 使用指南

使用 ImageIO 检查、解码、转码和编码图片，同时避免业务代码直接接触
Core Foundation 接口。

## 从 ImageReader 开始

使用编码后的 `Data` 或文件 URL 创建 ``ImageReader``。Reader 只检查一次输入，
并通过 ``ImageReader/descriptor`` 提供格式、像素尺寸、方向和帧数等稳定事实。

```swift
import WIImageIO

let reader = try ImageReader(imageData)
let descriptor = reader.descriptor
```

## 解码和编码

需要修改像素时，先将图片解码为 ``ImageFrame``。Frame 会一起持有像素、显示方向
以及编码时可继续使用的 metadata 来源。

```swift
let data = try reader
    .thumbnail(options: .init(maximumPixelSize: 1_280))
    .encode(
        as: .jpeg,
        options: .init(compressionQuality: 0.72)
    )
```

使用 ``ImageReader/image(options:)`` 解码完整图片，使用
``ImageReader/thumbnail(options:)`` 让 ImageIO 在解码阶段完成降采样。

## 不解码像素的转码

当操作不需要修改像素时，使用 ``ImageReader/transcode(as:options:)``。ImageIO
可以直接从编码源写入目标容器，无需将完整图片解码为位图。

```swift
let data = try reader.transcode(
    as: .jpeg,
    options: .init(metadata: .preserve)
)
```

## 调度边界

WIImageIO 的所有操作都是同步的。调用方负责决定在哪个 actor 或 executor 上执行，
并在这些同步 primitive 外部处理取消和任务优先级。

## 相关类型

- ``ImageDescriptor``
- ``ImageDecodeOptions``
- ``ImageThumbnailOptions``
- ``ImageTranscodeOptions``
- ``ImageEncodeOptions``
- ``ImageMetadataOptions``
- ``ImageIOError``
