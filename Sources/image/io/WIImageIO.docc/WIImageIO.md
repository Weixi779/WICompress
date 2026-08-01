# ``WIImageIO``

Inspect, decode, transcode, and encode image data without exposing ImageIO's
Core Foundation interfaces.

## Overview

Start with an ``ImageReader`` created from encoded `Data` or a file URL. The
reader inspects its input once and exposes the resulting facts through
``ImageReader/descriptor``.

```swift
import WIImageIO

let reader = try ImageReader(imageData)
let descriptor = reader.descriptor
```

Decode pixels when the image needs to be transformed. An ``ImageFrame`` keeps
the decoded pixels, display orientation, and available metadata provenance
together through encoding.

```swift
let data = try reader
    .thumbnail(options: .init(maximumPixelSize: 1_280))
    .encode(
        as: .jpeg,
        options: .init(compressionQuality: 0.72)
    )
```

Use ``ImageReader/transcode(as:options:)`` when ImageIO can write directly from
the encoded source without exposing decoded pixels.

```swift
let data = try reader.transcode(
    as: .jpeg,
    options: .init(metadata: .preserve)
)
```

All operations are synchronous. The caller owns scheduling, actor isolation,
and cancellation around these primitives.

For the Chinese guide, see <doc:Getting-Started-CN>.

## Topics

### Start Here

- <doc:Getting-Started-CN>
- ``ImageReader``
- ``ImageDescriptor``
- ``ImageFrame``

### Decoding

- ``ImageDecodeOptions``
- ``ImageThumbnailOptions``

### Transcoding and Encoding

- ``ImageTranscodeOptions``
- ``ImageEncodeOptions``
- ``ImageIOError``
