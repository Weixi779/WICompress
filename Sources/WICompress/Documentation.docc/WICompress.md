# WICompress

Compress JPEG, PNG, and HEIC image data with a small, predictable ImageIO-backed API.

## Overview

``WICompressor`` operates directly on original image `Data` or file `URL` input.
ImageIO handles format inspection, orientation, alpha, metadata, color profiles,
resizing, and encoding; every terminal returns one ``WIResult``.

The Process entry point declares one deterministic operation:

```swift
let result = try WICompressor.process(
    originalData,
    using: WIImageProcess(
        sizing: .resize(using: WIImageResize.maximumPixelSize(1600)),
        quality: 0.7,
        output: WIImageOutput(
            representation: .jpeg(background: .white),
            metadata: .strip,
            colorSpace: .convert(to: .sRGB)
        )
    )
)
```

The target-based entry point declares an output contract — a hard byte ceiling
plus optional base sizing — and searches quality and dimensions to satisfy it:

```swift
let thumbnail = try WICompressor.compress(
    originalData,
    to: WICompressionTarget(
        maxBytes: 32 * 1024,
        sizing: WICompressionSizing(
            maximumPixelSize: 200,
            aspectRatio: .square
        )
    )
)
```

All failures are thrown as ``WICompressError``; the core never imports UIKit or AppKit.

## Topics

### Essentials

- ``WICompressor``
- ``WIImageProcess``
- ``WICompressError``

### Process

- ``WIImageSizing``
- ``WIImageResizing``
- ``WIImageResize``
- ``WIImageCrop``
- ``WIPixelSize``

### Output

- ``WIImageOutput``
- ``WIImageRepresentation``
- ``WIJPEGBackground``
- ``WIImageMetadataOptions``
- ``WIImageColorSpace``

### Color Handling

- ``WIColorSpace``
- ``WIColor``

### Target-Based Compression

- ``WICompressionTarget``
- ``WICompressionSizing``
- ``WIAspectRatio``
- ``WICropAnchor``
- ``WIResult``

### Values

- ``WIImageFormat``
