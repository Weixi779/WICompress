# WIImageIO 操作模型

把 inspection、decode、transcode 与 encode 作为小而同步的操作使用。

## 先检查，再决定操作

``ImageDescriptor`` 只保存稳定源图事实，不暴露 `CGImageSource`。只有确实需要具体
源色彩空间时才调用 ``ImageReader/colorSpace()``；解析色彩空间可能会解码源图像素。

Runtime capability 取决于当前平台提供的 ImageIO 实现：

```swift
let canRead = ImageReader.canDecode(.heic)
let canWrite = ImageReader.canEncode(.heic)
```

## 解码存储像素或展示像素

使用 ``ImageReader/image(options:)`` 获取完整存储帧。它的
``ImageFrame/orientation`` 仍然明确存在，``ImageFrame/pixelSize`` 描述存储像素行。

使用 ``ImageReader/thumbnail(options:)`` 让 ImageIO 在解码阶段降采样。默认行为会
应用展示方向并返回 `.up` Frame。只有调用方准备自行处理方向时，才将
`appliesOrientationTransform` 设为 `false`。

两种操作都只支持静态图片。多帧输入会抛出
``ImageIOError/animatedSourceUnsupported(frameCount:)``，而不是静默选择第一帧。

## 转码编码源

当目标格式、quality、尺寸与 metadata 操作可以直接基于编码源完成时，使用
``ImageReader/transcode(as:options:)``：

```swift
let output = try reader.transcode(
    as: .jpeg,
    options: ImageTranscodeOptions(
        compressionQuality: 0.8,
        metadata: .preserve
    )
)
```

Transcode 默认保留 metadata。如果当前路径无法安全表达请求的 metadata 变更，会抛出
``ImageIOError/metadataTranscodeUnsupported(_:)``。需要修改像素时应改用 decode 与
encode。

## 编码解码像素或调用方像素

Reader 解码得到的 Frame 会保留内部 metadata 快照。调用方也可以包装自己的像素：

```swift
let frame = ImageFrame(image: cgImage, orientation: .up)
let output = try frame.encode(as: .png)
```

Encode 默认移除 metadata。传入 `.preserve` 只会保留来自 Reader 的已建模 metadata；
调用方创建的 Frame 没有 provenance。

## 调度边界属于调用方

WIImageIO 有意保持同步，不提供 queue、Task wrapper、全局 registry 或取消策略。
应用应在自己选择的执行上下文中创建并消费 Reader，而不是让其 ImageIO handle 跨并发
Domain 共享。

更高层的 `WICompress` product 提供可取消的 async terminal。内部 Pipeline 所有权见
[架构文档](https://github.com/Weixi779/WICompress/blob/main/docs/architecture/README_CN.md)。
