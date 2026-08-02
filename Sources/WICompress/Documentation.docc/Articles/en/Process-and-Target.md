# Process and Target

Choose between a deterministic image operation and a feedback search with a hard byte ceiling.

## Declare a Process

``WIImageProcess`` groups four facts that describe one operation:

- `crop` optionally chooses an aspect-ratio region.
- `sizing` resolves the cropped pixel size.
- `quality` supplies a lossy encoder quality, or `nil` to leave it unspecified.
- `output` declares representation, metadata, and color-space requirements.

```swift
let process = WIImageProcess(
    sizing: .resize(using: WIImageResize.maximumPixelSize(1_600)),
    quality: 0.72,
    output: WIImageOutput(
        representation: .pngIfAlphaOtherwiseJPEG,
        metadata: .strip,
        colorSpace: .preserve
    )
)

let result = try await WICompressor.process(input, using: process)
```

Cropping always happens before resizing. Anchors use normalized top-left-origin
coordinates and are clamped to `0...1`.

```swift
let crop = try WIImageCrop.aspectRatio(
    width: 4,
    height: 3,
    anchor: WICropAnchor(x: 0.5, y: 0.25)
)

let result = try await WICompressor.process(
    input,
    using: WIImageProcess(crop: crop)
)
```

Built-in resizing includes Luban V2, the corrected Luban 1 behavior, longest-side
limits, two-dimensional proportional constraints, explicit scaling, and exact sizes.
Custom implementations only need to conform to ``WIImageResizing`` and return one
complete target pixel size.

## Declare a Target

``WICompressionTarget`` is for external constraints such as an upload or sharing
SDK that rejects files above a fixed byte count. WICompress searches candidate
quality and dimensions, then verifies the final result against `maxBytes`.
Its default output uses PNG for alpha sources and JPEG otherwise, strips non-display
metadata, and converts rendered pixels to sRGB.

```swift
let target = try WICompressionTarget(
    maxBytes: 500_000,
    sizing: WICompressionSizing(maximumPixelSize: 1_600)
)

let result = try await WICompressor.compress(input, to: target)
```

An optional aspect ratio adds one concrete crop before the search:

```swift
let square = try WIAspectRatio(width: 1, height: 1)
let target = try WICompressionTarget(
    maxBytes: 250_000,
    sizing: WICompressionSizing(
        maximumPixelSize: 1_080,
        aspectRatio: square,
        anchor: .center
    )
)
```

Target has no caller-selected quality. Quality and any additional size reduction are
search variables owned by the compressor. If the supported output path cannot satisfy
the hard limit, the operation throws ``WICompressError/targetUnsatisfiable(smallestByteCount:)``.

## Share output requirements

Process and Target use the same ``WIImageOutput``. Representation, metadata, and
color-space requirements therefore keep the same meaning on both paths.

For the internal search and pipeline design, see the
[architecture documentation](https://github.com/Weixi779/WICompress/blob/main/docs/architecture/README.md).
