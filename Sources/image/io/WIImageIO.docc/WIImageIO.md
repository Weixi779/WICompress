# ``WIImageIO``

Inspect, decode, transcode, and encode static images without exposing Core Foundation interfaces.

## Overview

Create an ``ImageReader`` from encoded `Data` or a file URL. The reader inspects its
input once and exposes stable source facts through ``ImageReader/descriptor``.

```swift
import UniformTypeIdentifiers
import WIImageIO

let reader = try ImageReader(imageData)
let descriptor = reader.descriptor
```

Decode a thumbnail when pixels need to be transformed, then encode its ``ImageFrame``:

```swift
let data = try reader
    .thumbnail(options: .init(maximumPixelSize: 1_280))
    .encode(
        as: .jpeg,
        options: .init(compressionQuality: 0.72)
    )
```

Use ``ImageReader/transcode(as:options:)`` when ImageIO can write from the encoded
source without exposing decoded pixels.

All WIImageIO operations are synchronous. The caller owns scheduling, actor isolation,
priority, and cancellation around these request-scoped primitives.

For module ownership and WICompress pipeline integration, see the
[architecture documentation](https://github.com/Weixi779/WICompress/blob/main/docs/architecture/README.md).

## Topics

### Start Here

- <doc:ImageIO-Getting-Started>
- <doc:ImageIO-Operations>

### 中文指南

- <doc:ImageIO-Getting-Started-CN>
- <doc:ImageIO-Operations-CN>

### Inspection

- ``ImageReader``
- ``ImageReader/init(_:)``
- ``ImageReader/init(contentsOf:)``
- ``ImageReader/inspect(_:)``
- ``ImageReader/inspect(contentsOf:)``
- ``ImageReader/descriptor``
- ``ImageDescriptor``
- ``ImageReader/colorSpace()``

### Decoding

- ``ImageReader/image(options:)``
- ``ImageReader/thumbnail(options:)``
- ``ImageDecodeOptions``
- ``ImageThumbnailOptions``
- ``ImageFrame``

### Transcoding and Encoding

- ``ImageReader/transcode(as:options:)``
- ``ImageTranscodeOptions``
- ``ImageFrame/init(image:orientation:)``
- ``ImageFrame/encode(as:options:)``
- ``ImageEncodeOptions``

### Runtime Capabilities

- ``ImageReader/canDecode(_:)``
- ``ImageReader/canEncode(_:)``
- ``ImageIOError``

### Shared Image Values

- ``ImageFormat``
- ``WIPixelSize``
- ``WIImageOrientation``
- ``ImageMetadataOptions``
- ``WIColorSpace``
- ``WIColor``
