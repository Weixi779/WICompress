# ``WICompress``

Process JPEG, PNG, and HEIC images with explicit pixel operations or a hard byte target.

## Overview

WICompress operates on encoded `Data` or file URLs and always returns a ``WIResult``.
It coordinates ImageIO and Core Graphics while keeping UIKit and AppKit out of the
compression core.

Use Process when you already know the pixel operation and output requirements:

```swift
let result = try await WICompressor.process(
    originalData,
    using: WIImageProcess(
        sizing: .resize(using: WIImageResize.maximumPixelSize(1_600)),
        quality: 0.7,
        output: WIImageOutput(
            representation: .jpeg(background: .white),
            metadata: .strip,
            colorSpace: .convert(to: .sRGB)
        )
    )
)
```

Use Target when the encoded result must not exceed a concrete byte count:

```swift
let result = try await WICompressor.compress(
    originalData,
    to: WICompressionTarget(maxBytes: 500_000)
)
```

Every Data and file terminal has synchronous and asynchronous forms. Async work does
not occupy the caller's actor and preserves the standard `CancellationError`.

For implementation ownership, module dependencies, and pipeline internals, see the
[architecture documentation](https://github.com/Weixi779/WICompress/blob/main/docs/architecture/README.md).

## Topics

### Start Here

- <doc:Getting-Started>
- <doc:Process-and-Target>
- <doc:Concurrency-and-Cancellation>
- <doc:Migrating-to-2.0>

### 中文指南

- <doc:Getting-Started-CN>
- <doc:Process-and-Target-CN>
- <doc:Concurrency-and-Cancellation-CN>
- <doc:Migrating-to-2.0-CN>

### Terminals and Results

- ``WICompressor``
- ``WIResult``
- ``WICompressError``

### Process

- ``WIImageProcess``
- ``WIImageSizing``
- ``WIImageResizing``
- ``WIImageResize``
- ``WIImageCrop``
- ``WIAspectRatio``
- ``WICropAnchor``

### Target-Based Compression

- ``WICompressionTarget``
- ``WICompressionSizing``

### Output

- ``WIImageOutput``
- ``WIImageRepresentation``
- ``WIJPEGBackground``
- ``ImageMetadataOptions``
- ``WIImageColorSpace``
- ``WIColorSpace``
- ``WIColor``

### Image Values

- ``ImageFormat``
- ``WIPixelSize``
- ``WIImageOrientation``
