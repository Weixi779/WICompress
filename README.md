# WICompress

[![CI](https://github.com/Weixi779/WICompress/actions/workflows/ci.yml/badge.svg)](https://github.com/Weixi779/WICompress/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-blue)
![Swift](https://img.shields.io/badge/Swift-6.2%2B-orange)
![SPM Support](https://img.shields.io/badge/SPM-Supported-brightgreen)
![License](https://img.shields.io/github/license/Weixi779/WICompress)

English | [简体中文](README_CN.md)

Compress images for upload with a small, predictable Swift API.

`WICompress` is an ImageIO-backed Swift image compression library that operates
directly on original image `Data` or file `URL` input. ImageIO handles format
inspection, orientation, alpha, metadata, color profiles, resizing, and encoding;
the public API stays simple and returns one `WIResult`.

It preserves JPEG/PNG/HEIC by default, can convert to an explicit output format
or choose PNG/JPEG from alpha-channel presence, strips metadata for privacy, and
resizes images without depending on `UIImage` or `NSImage`.

```swift
let result = try WICompressor.process(originalData)
```

```swift
let uploadData = try WICompressor.process(
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
).data
```

## Why WICompress

- **Data in, structured result out**: keep picker/file/network bytes, then use
  the encoded data, format, pixel size, and byte count from one `WIResult`.
- **Upload-ready defaults**: Luban resize, metadata stripping, and JPEG/HEIC
  lossy quality are configured for common app uploads.
- **Selective metadata**: preserve Exif, IPTC, TIFF, maker notes, or standard
  GPS independently; `.preserve.subtracting(.gps)` keeps the remaining
  metadata while removing GPS properties exposed by ImageIO.
- **Target contracts**: use `maxBytes` with geometry intent when an SDK or
  backend requires a hard byte ceiling.
- **Composable processing**: choose crop, resizing, quality, and output as
  independent parts of one deterministic `WIImageProcess`.
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

## Requirements and Installation

- iOS 14+ / macOS 11+ / Mac Catalyst 14+ / tvOS 14+ / watchOS 7+ / visionOS 1+
- Swift 6.2+ (Xcode 26+)

Add WICompress to your project with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/Weixi779/WICompress.git", from: "2.0.0")
]
```

The package publishes two library products. Use `WICompress` for compression
terminals. Use `WIImageIO` only when a lower-level typed ImageIO chain is the
actual requirement.

## Compression Preview

The comparison image below is generated from repository fixtures with
`scripts/generate-doc-assets.swift`, so it can be regenerated when compression
behavior changes.

```bash
swift run WICompressDocAssetGenerator
```

![WICompress compression comparison](docs/assets/compression-comparison.png)

The preview uses the default API for most rows and includes one target-based
sharing thumbnail row built from an explicit `WICompressionTarget`. It shows
three HEIC photos first because HEIC is the most important real-world case, then
JPEG and PNG examples. PNG is not skipped: the panoramic screenshot shrinks when
Luban resize is triggered, while the alpha PNG is a no-op case where the
original data is already the better result.

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

let result = try WICompressor.process(originalData)
```

Compress a file URL:

```swift
let result = try WICompressor.process(contentsOf: imageURL)
```

Declare an explicit process:

```swift
let result = try WICompressor.process(
    originalData,
    using: WIImageProcess(
        sizing: .resize(using: WIImageResize.luban),
        quality: 0.7,
        output: WIImageOutput(
            representation: .preserve,
            metadata: .strip,
            colorSpace: .preserve
        )
    )
)
```

Crop and resize in one operation:

```swift
let asset = try WICompressor.process(
    originalData,
    using: WIImageProcess(
        sizing: .resize(
            using: WIImageResize.constrained(
                within: WIPixelSize(width: 400, height: 467)
            )
        ),
        crop: .aspectRatio(width: 1, height: 1),
        quality: 0.7,
        output: WIImageOutput(
            representation: .pngIfAlphaOtherwiseJPEG
        )
    )
)
```

Compress to a hard byte target:

```swift
let thumbnail = try WICompressor.compress(
    originalData,
    to: WICompressionTarget(
        maxBytes: 32 * 1024,
        sizing: WICompressionSizing(
            maximumPixelSize: 200,
            aspectRatio: WIAspectRatio(width: 1, height: 1)
        ),
        output: WIImageOutput(
            representation: .jpeg(background: .white),
            metadata: .strip,
            colorSpace: .convert(to: .sRGB)
        )
    )
)

print(thumbnail.byteCount)
print(thumbnail.pixelSize)
```

## Lower-Level ImageIO

`WIImageIO` is a separate synchronous product for inspection, decoding,
thumbnailing, source transcoding, and encoding without exposing `CGImageSource`,
`CGImageDestination`, or property dictionaries:

```swift
import WIImageIO

let reader = try ImageReader(originalData)
let descriptor = reader.descriptor

let encoded = try reader
    .thumbnail(options: .init(maximumPixelSize: 1200))
    .encode(
        as: .jpeg,
        options: .init(compressionQuality: 0.75)
    )
```

The chain preserves source metadata provenance and orientation where the chosen
options allow it. It throws `ImageIOError`; scheduling and actor hops remain
the caller's responsibility.

See [Getting Started with WIImageIO](Sources/image/io/WIImageIO.docc/WIImageIO.md)
for the complete lower-level flow.

## Working With UIKit or AppKit

`WICompress` does not take `UIImage` or `NSImage`. Keep the original image data
from your picker, file, network response, or database, pass that data to
`WICompress`, and decode the result at the UI boundary if you need a preview.

```swift
guard let originalData = try await photosPickerItem.loadTransferable(type: Data.self) else {
    throw MyError.missingImageData
}

let result = try WICompressor.process(originalData)
let previewImage = UIImage(data: result.data)
```

This shape avoids asking callers to pass both a rendered image and separate
format data. ImageIO can inspect dimensions, orientation, format, and metadata
directly from the original bytes.

## Image Process

`WIImageProcess` describes one deterministic operation. Its default uses the
Luban-derived resizing algorithm, quality `0.6`, source representation,
stripped metadata, and preserved color-space semantics.

```swift
public struct WIImageProcess {
    public let sizing: WIImageSizing
    public let crop: WIImageCrop?
    public let quality: Double?
    public let output: WIImageOutput
}
```

Sizing deliberately has only two branches: keep the current pixels or ask a
`WIImageResizing` implementation for a complete target size. Built-ins include
`luban`, `maximumPixelSize`, `constrained`, `scaled`, and `exact`. Applications
can implement `WIImageResizing` when sizing follows product-specific rules.

Crop is an optional aspect ratio plus a normalized `WICropAnchor`; it is
resolved before resizing. Output independently declares representation
(`preserve`, JPEG, PNG, HEIC, or alpha-aware PNG/JPEG), metadata categories,
and color space (`preserve` / `convert`). Metadata defaults to `.strip`;
`.preserve` retains every supported category, and standard `OptionSet`
operations can select a subset:

```swift
let metadata = ImageMetadataOptions.preserve.subtracting(.gps)
```

Quality is a fixed `0...1` value for lossy output, or `nil` to omit an explicit
ImageIO quality value. PNG remains lossless. Transparent sources converted to
JPEG require an explicit `WIJPEGBackground`.

## Target Compression

`WICompressionTarget` is for APIs that need output bytes to satisfy a contract,
for example "thumbnail data must be under 32 KB." Unlike Process, the compressor
controls quality, dimensions, and attempt count internally.

```swift
public struct WICompressionTarget {
    public let maxBytes: Int
    public let sizing: WICompressionSizing
    public let output: WIImageOutput
}

public struct WICompressionSizing {
    public let maximumPixelSize: Int?
    public let aspectRatio: WIAspectRatio?
    public let anchor: WICropAnchor
}
```

The Target default output writes PNG for Alpha sources and JPEG otherwise,
strips metadata, and converts pixels to sRGB. Passing an explicit
`WIImageOutput` replaces that product default with the stated requirements.

Sizing defines the base candidate before byte search begins:

- With neither value, search starts from the oriented source pixel size.
- `maximumPixelSize` proportionally caps the longest side and never upscales.
- `aspectRatio` takes the largest crop at that ratio, positioned by `anchor`.
- With both values, WICompress crops first and then applies the pixel bound.

`anchor` uses normalized `0...1` top-left-origin coordinates and defaults to the
center. The ratio and crop are resolved once; the solver only searches a uniform
scale and lossy quality. JPEG and HEIC search quality before reducing dimensions.
PNG stays lossless and reduces dimensions. If no result can satisfy both the
output contract and byte ceiling, WICompress throws
`WICompressError.targetUnsatisfiable`.

Every terminal returns `WIResult`, including the encoded `Data`,
container format, integer pixel size, and byte count.

WICompress does not ship platform-specific sharing presets. Sharing SDK rules
and recommendations change over time, so application code should define its own
targets from the current SDK documentation and product requirements.

## Error Handling

All public APIs throw `WICompressError`.

```swift
do {
    let result = try WICompressor.process(data)
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
- `invalidTarget`
- `targetUnsatisfiable`
- `resourceLimitExceeded`
- `thumbnailCreationFailed`
- `imageDecodeFailed`
- `destinationCreationFailed`
- `encodeFailed`

## Current Limits

WICompress intentionally does not include:

- `UIImage` / `NSImage` convenience adapters
- Live Photo compression
- async API
- GPS-only metadata stripping
- HDR gain map preservation
- animated image output
- WebP / JPEG XL writing

For Live Photos, compressing the still image resource alone is not enough: the
paired video resource and pairing metadata also need to be handled. That belongs
in a Photos-level workflow, not the v1 ImageIO core.

## Upgrading to 2.0

WICompress 2.0 replaces the 1.x options and policy surface with the Process and
Target domains shown above. The package import remains `WICompress`, while the
static terminal is now `WICompressor`. See
[the 2.0 migration guide](docs/V2_MIGRATION_CN.md) and
[CHANGELOG.md](CHANGELOG.md) for details.

## License

WICompress is available under the Apache-2.0 license. See `LICENSE.txt` for details.
