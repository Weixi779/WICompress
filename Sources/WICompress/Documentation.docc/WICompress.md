# ``WICompress``

Compress JPEG, PNG, and HEIC image data with a small, predictable ImageIO-backed API.

## Overview

WICompress operates directly on original image `Data` or file `URL` input.
ImageIO handles format inspection, orientation, alpha, metadata, color profiles,
resizing, and encoding; the public API stays simple and returns compressed bytes.

The upload-style entry point applies ``WICompressOptions`` policies and returns `Data`:

```swift
let uploadData = try WICompress.compress(
    originalData,
    options: WICompressOptions(
        resize: .maxPixel(1600),
        format: .jpeg(background: .white),
        metadata: .strip,
        quality: .compression(0.7)
    )
)
```

The target-based entry point declares an output contract — a hard byte ceiling
plus geometry — and searches quality and dimensions to satisfy it:

```swift
let thumbnail = try WICompress.compress(
    originalData,
    to: WICompressionTarget(
        maxBytes: 32 * 1024,
        geometry: .fill(size: WISize(width: 200, height: 200))
    )
)
```

All failures are thrown as ``WICompressError``; the core never imports UIKit or AppKit.

## Topics

### Essentials

- ``WICompress/WICompress``
- ``WICompressOptions``
- ``WICompressError``

### Compression Policies

- ``WIResizePolicy``
- ``WIFormatPolicy``
- ``WIJPEGBackground``
- ``WIMetadataPolicy``
- ``WIQualityPolicy``

### Color Handling

- ``WIOutputColorSpace``
- ``WIColorSpace``
- ``WIColor``

### Target-Based Compression

- ``WICompressionTarget``
- ``WICompressionGeometry``
- ``WICropMode``
- ``WIImagePlacement``
- ``WICompressionOutput``
- ``WICompressionPreference``
- ``WICompressionResult``

### Values

- ``WISize``
- ``WIImageFormat``
