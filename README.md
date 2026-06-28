# WICompress

![Platform](https://img.shields.io/badge/platform-iOS%2014.0%2B%20%7C%20macOS%2011.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange)
![SPM Support](https://img.shields.io/badge/SPM-Supported-brightgreen)
![License](https://img.shields.io/github/license/Weixi779/WICompress)

English | [简体中文](README_CN.md)

Compress images for upload with a small, predictable Swift API.

`WICompress` is an ImageIO-backed Swift image compression library that operates
directly on original image `Data` or file `URL` input. ImageIO handles format
inspection, orientation, alpha, metadata, color profiles, resizing, and encoding;
the public API stays simple and returns compressed `Data`.

It preserves JPEG/PNG/HEIC by default, can convert to an explicit output format
or choose PNG/JPEG from alpha-channel presence, strips metadata for privacy, and
resizes images without depending on `UIImage` or `NSImage`.

```swift
let compressedData = try WICompress.compress(originalData)
```

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

## Why WICompress

- **Data in, Data out**: keep picker/file/network bytes and pass them directly
  to the compressor.
- **Upload-ready defaults**: Luban resize, metadata stripping, and JPEG/HEIC
  lossy quality are configured for common app uploads.
- **Flexible resize policies**: use Luban, cap the longest side, or fit an image
  into caller-supplied minimum/maximum display dimensions.
- **Format control**: preserve the source container or explicitly output JPEG,
  PNG, HEIC, or choose PNG for alpha-channel sources and JPEG otherwise.
- **Alpha-safe JPEG conversion**: transparent sources require an explicit white
  or black background instead of silently flattening.
- **Orientation-safe resizing**: display dimensions are resolved from ImageIO
  metadata, then redraw paths bake orientation into pixels.
- **UIKit/AppKit-free core**: the compression pipeline works in iOS apps,
  macOS tools, and SwiftPM tests without UI image types.
- **Typed failures**: errors are surfaced as `WICompressError`, not optional
  `nil` results.

## Compression Preview

The comparison image below is generated from repository fixtures with
`scripts/generate-doc-assets.swift`, so it can be regenerated when compression
behavior changes.

```bash
swift run WICompressDocAssetGenerator
```

![WICompress compression comparison](docs/assets/compression-comparison.png)

The preview uses the default API for every row. It shows three HEIC photos first
because HEIC is the most important real-world case, then JPEG and PNG examples.
PNG is not skipped: the panoramic screenshot shrinks when Luban resize is
triggered, while the alpha PNG is a no-op case where the original data is
already the better result.

## Example Project

The repository includes a SwiftUI example app:

1. Open `Example/WICompressExample/WICompressExample.xcodeproj`.
2. Build and run on an iOS device or simulator.
3. Pick an image and compare the original data with the compressed data.

The example demonstrates:

- `PhotosPicker` and `PHPickerViewController` data loading
- raw `Data` compression
- format detection
- original/compressed preview
- file-size and compression-ratio display

## API Examples

```swift
import WICompress

let compressedData = try WICompress.compress(originalData)
```

Compress a file URL:

```swift
let compressedData = try WICompress.compress(contentsOf: imageURL)
```

Use explicit options:

```swift
let compressedData = try WICompress.compress(
    originalData,
    options: WICompressOptions(
        resize: .luban,
        format: .preserve,
        metadata: .strip,
        quality: .compression(0.7)
    )
)
```

Fit image assets into a caller-defined display-size range:

```swift
let assetData = try WICompress.compress(
    originalData,
    options: WICompressOptions(
        resize: .fit(
            minSize: WISize(width: 40, height: 50),
            maxSize: WISize(width: 400, height: 467)
        ),
        format: .pngIfAlphaOtherwiseJPEG,
        metadata: .strip,
        quality: .compression(0.7)
    )
)
```

## Working With UIKit or AppKit

`WICompress` does not take `UIImage` or `NSImage`. Keep the original image data
from your picker, file, network response, or database, pass that data to
`WICompress`, and decode the result at the UI boundary if you need a preview.

```swift
guard let originalData = try await photosPickerItem.loadTransferable(type: Data.self) else {
    throw MyError.missingImageData
}

let compressedData = try WICompress.compress(originalData)
let previewImage = UIImage(data: compressedData)
```

This shape avoids asking callers to pass both a rendered image and separate
format data. ImageIO can inspect dimensions, orientation, format, and metadata
directly from the original bytes.

## Options

`WICompressOptions.default` is tuned for upload-style compression:

```swift
WICompressOptions(
    resize: .luban,
    format: .preserve,
    metadata: .strip,
    quality: .compression(0.6),
    colorSpace: .preserve
)
```

### Resize

```swift
public struct WISize {
    public var width: Double
    public var height: Double
}

public enum WIResizePolicy {
    case none
    case luban
    case maxPixel(Int)
    case fit(minSize: WISize, maxSize: WISize)
}
```

- `.luban`: default. Downsamples large images using the Luban ratio.
- `.maxPixel(value)`: caps the longest display side to `value` pixels and never
  upscales smaller images.
- `.fit(minSize:maxSize:)`: keeps aspect ratio, upscales only when both display
  sides are below `minSize`, downscales when either side exceeds `maxSize`, and
  leaves the image unchanged when it is already within `maxSize` and not below
  `minSize`. This policy can enlarge small bitmap assets; the core remains
  UIKit/AppKit-free.
- `.none`: keeps the source display dimensions.

### Format

```swift
public enum WIJPEGBackground {
    case disallow
    case white
    case black
    case color(WIColor)
}

public enum WIFormatPolicy {
    case preserve
    case jpeg(background: WIJPEGBackground = .disallow)
    case pngIfAlphaOtherwiseJPEG
    case png
    case heic
}
```

- `.preserve`: default. Keeps the source image container.
- `.jpeg(background:)`: writes JPEG. Transparent sources require `.white`,
  `.black`, or `.color(WIColor)`; `.disallow` throws instead of silently
  flattening alpha.
- `.pngIfAlphaOtherwiseJPEG`: writes PNG when the source has an alpha channel,
  otherwise writes JPEG.
- `.png`: writes PNG. The quality policy is ignored because PNG is lossless.
- `.heic`: writes HEIC when the current platform can encode it.

Explicit format conversion and alpha-aware format selection always rewrite the
image. The size guard will not return original bytes when the caller requested a
non-preserving destination policy.

### Metadata

```swift
public enum WIMetadataPolicy {
    case strip
    case preserve
}
```

- `.strip`: default. Removes strippable metadata such as Exif/GPS/TIFF/maker
  dictionaries when rewriting is required.
- `.preserve`: keeps normal metadata and orientation tags by using the
  source-copy write path when possible.

When format conversion forces the redraw path, `.preserve` re-attaches ordinary
metadata dictionaries where ImageIO supports them. Orientation is still baked
into pixels and reset to `1`, because preserving the original rotation tag after
redraw would double-rotate readers.

Color profiles are display semantics, not privacy metadata. Display P3 profiles
are expected to survive both source-copy and redraw paths.

HDR gain maps are not preserved by the initial public release. They require a
separate policy and test contract because gain maps are auxiliary image data,
not ordinary Exif/GPS metadata.

### Color Space

```swift
public enum WIColorSpace {
    case sRGB
    case displayP3
    case iccProfile(Data)
}

public enum WIOutputColorSpace {
    case preserve
    case convert(to: WIColorSpace)
    case preserveIfSupported(Set<WIColorSpace>, otherwise: WIColorSpace)
}

public struct WIColor {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public var colorSpace: WIColorSpace
}
```

- `.preserve`: default. Keeps normal source display semantics. RGB profiles
  such as Display P3 survive copy and redraw paths when ImageIO can represent
  them.
- `.convert(to:)`: redraws into the requested color space. Explicit conversion
  is never bypassed by the size guard.
- `.preserveIfSupported(_:otherwise:)`: keeps known supported spaces, such as
  sRGB and Display P3, and converts unsupported or unknown sources to the
  fallback.

Color-space inspection is lazy. The default `.preserve` policy does not decode
pixels only to identify the source profile.

### Quality

```swift
public enum WIQualityPolicy {
    case none
    case compression(Double)
}
```

- `.compression(value)`: clamps `value` into `0.0...1.0` and applies it to
  lossy destination formats such as JPEG and HEIC.
- `.none`: does not set `kCGImageDestinationLossyCompressionQuality`.

`.none` does not mean lossless and does not promise byte-for-byte output unless
the write plan can safely return the original data.

PNG is lossless; the quality policy is intentionally a no-op for PNG.

## Error Handling

All public APIs throw `WICompressError`.

```swift
do {
    let compressedData = try WICompress.compress(data)
} catch let error as WICompressError {
    // Decide whether to show an error, retry, or keep the original data.
    print(error)
}
```

Common cases:

- `invalidImageData`
- `imageInfoUnavailable`
- `unsupportedSourceFormat`
- `unsupportedDestinationFormat`
- `transparentSourceRequiresBackground`
- `unsupportedColorSpace`
- `invalidICCProfile`
- `colorConversionFailed`
- `nonOpaqueJPEGBackground`
- `animatedSourceUnsupported`
- `thumbnailCreationFailed`
- `destinationCreationFailed`
- `encodeFailed`

## Current Limits

WICompress intentionally does not include:

- `UIImage` / `NSImage` convenience adapters
- Live Photo compression
- async API
- GPS-only metadata stripping
- target-byte-size compression
- HDR gain map preservation
- animated image output
- WebP / JPEG XL writing

For Live Photos, compressing the still image resource alone is not enough: the
paired video resource and pairing metadata also need to be handled. That belongs
in a Photos-level workflow, not the v1 ImageIO core.

## Upgrading From 0.x

WICompress 1.0.0 replaces the old `UIImage`-oriented API with the `Data`/`URL`
core API shown above. See [CHANGELOG.md](CHANGELOG.md) for the breaking change
summary.

## License

WICompress is available under the Apache-2.0 license. See `LICENSE.txt` for details.
