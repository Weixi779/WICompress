# Migrating to WICompress 2.0

[简体中文](MIGRATION_2_CN.md)

WICompress 2.0 is an intentional breaking release. Projects that need the 1.x
API or a toolchain older than Swift 6.2 should remain on the latest 1.x release.

## Requirements

WICompress 2.0 requires Swift 6.2 and uses Swift 6 language mode. Deployment
targets remain iOS 14, macOS 11, Mac Catalyst 14, tvOS 14, watchOS 7, and
visionOS 1 or later.

The package and high-level product remain named `WICompress`:

```swift
import WICompress
```

The package also publishes the independent `WIImageIO` product for lower-level
ImageIO work.

## Terminal namespace

Static high-level terminals moved from `WICompress` to `WICompressor`:

| 1.x | 2.0 |
| --- | --- |
| `WICompress.compress(_:options:)` | `WICompressor.process(_:using:)` |
| `WICompress.compress(contentsOf:options:)` | `WICompressor.process(contentsOf:using:)` |
| `WICompress.compress(_:to:)` | `WICompressor.compress(_:to:)` |
| `WICompress.compress(contentsOf:to:)` | `WICompressor.compress(contentsOf:to:)` |

`WICompressor` is an uninhabited namespace. There is no `.shared` singleton,
deprecated wrapper, or compatibility alias.

## Replace Options and Policy

2.0 does not carry the 1.x policy object forward. Choose the API from the result
contract:

- Use `WIImageProcess` when the caller knows crop, resizing, quality, and output.
- Use `WICompressionTarget` when the final encoded data must not exceed
  `maxBytes`.

```swift
let processed = try WICompressor.process(
    imageData,
    using: WIImageProcess(
        sizing: .resize(using: WIImageResize.maximumPixelSize(1_600)),
        quality: 0.7
    )
)

let constrained = try WICompressor.compress(
    imageData,
    to: WICompressionTarget(maxBytes: 500_000)
)
```

Process and Target both return `WIResult`. Code that previously expected `Data`
should read `result.data`; format, pixel size, and byte count come from the same
result.

## Migrate 1.x Target contracts

The 1.x `WICompressionGeometry` mixed soft sizing, hard crop/canvas geometry,
and placement. In 2.0, `WICompressionSizing` describes only the base pixels from
which byte-target search begins. The search may reduce those dimensions to
satisfy `maxBytes`; a Target can no longer require both an exact pixel canvas
and a hard byte ceiling.

| 1.x Target geometry | 2.0 migration | Semantic difference |
| --- | --- | --- |
| `.original` | `WICompressionSizing.original` | Same source-sized starting point; both versions may reduce dimensions to meet the byte target. |
| `.fit(maxLongSide:)` | `WICompressionSizing(maximumPixelSize:)` | Same proportional longest-side cap; search may reduce it further. A non-positive 1.x value failed during execution, while 2.0 normalizes it to `1`. |
| `.fitInside(box:)` | A square box maps to `maximumPixelSize`. For any other box, resolve a proportional size from the inspected source, then pass its longest side. | There is no general one-to-one Target mapping. If a byte ceiling is not required, Process with `WIImageResize.constrained(within:)` directly expresses the two-dimensional bound. |
| `.fill(size:crop:)` | Use `aspectRatio`, `maximumPixelSize`, and `anchor` for a soft Target crop, or `WIImageCrop` plus `WIImageResize.exact(_:)` in Process. | 1.x required the exact size and could upscale. A 2.0 Target does not upscale and may shrink further; Process preserves exact size but does not search for `maxBytes`. |
| `.exactCanvas(size:placement:background:)` | No one-to-one replacement. Compose padding, placement, or a canvas outside WICompress. | 2.0 intentionally does not model UI-style canvas layout in Target. A stretch-only case can use Process with `WIImageResize.exact(_:)`; `WIJPEGBackground` flattens source transparency and is not a canvas background. |

For aspect-ratio crop, `WICropMode` is replaced by normalized, top-left-origin
`WICropAnchor` coordinates:

| 1.x crop | 2.0 anchor |
| --- | --- |
| `.center` | `.center` (`0.5, 0.5`) |
| `.top` / `.bottom` | `WICropAnchor(x: 0.5, y: 0)` / `WICropAnchor(x: 0.5, y: 1)` |
| `.left` / `.right` | `WICropAnchor(x: 0, y: 0.5)` / `WICropAnchor(x: 1, y: 0.5)` |
| `.topLeft` / `.topRight` | `WICropAnchor(x: 0, y: 0)` / `WICropAnchor(x: 1, y: 0)` |
| `.bottomLeft` / `.bottomRight` | `WICropAnchor(x: 0, y: 1)` / `WICropAnchor(x: 1, y: 1)` |

The remaining Target types migrate as follows:

| 1.x | 2.0 |
| --- | --- |
| `WICompressionOutput` | `WIImageOutput`; `format`, `metadata`, and `colorSpace` become `representation`, `metadata`, and `colorSpace`. |
| `WIFormatPolicy` | `WIImageRepresentation`; the preserve, JPEG, alpha-aware, PNG, and HEIC cases correspond directly. |
| `WIMetadataPolicy` | `ImageMetadataOptions`; `.strip` and `.preserve` remain, with additional category-level selection. |
| `WIOutputColorSpace.preserve` / `.convert(to:)` | `WIImageColorSpace.preserve` / `.convert(to:)`. |
| `WICompressionOutput.upload` or `WICompressionOutput()` | No preset has identical semantics. Construct the alpha-aware, strip, preserve-color output shown below. The 2.0 Target default converts rendered output to sRGB. |
| `WICompressionOutput.preserve` | Construct `WIImageOutput(representation: .preserve, metadata: .preserve, colorSpace: .preserve)`. |
| `WIOutputColorSpace.preserveIfSupported` | No direct replacement. Inspect the source color space, then choose `.preserve` or `.convert(to:)` in application code. |
| `WICompressionPreference` | Removed without replacement. Target search has one deterministic candidate ordering. |
| `WISize` | Use `WIPixelSize` for concrete integer pixels and `WIAspectRatio` for a ratio; there is no single compatibility alias. |
| `WICompressionResult` | `WIResult`; Target and Process now share one result, `format` uses `ImageFormat`, `pixelSize` uses `WIPixelSize`, and `byteCount` is derived from `data.count`. |

To preserve the 1.x default Target output semantics, pass the output explicitly:

```swift
let target = try WICompressionTarget(
    maxBytes: 500_000,
    output: WIImageOutput(
        representation: .pngIfAlphaOtherwiseJPEG,
        metadata: .strip,
        colorSpace: .preserve
    )
)
```

`WICompressionTarget` construction now validates `maxBytes` and therefore
throws `WICompressError`; its public request properties are immutable in 2.0.
`WIImageOutput()` is the Process-oriented default and is not the default output
used by `WICompressionTarget`.

## Default resizing

The default Process sizing algorithm is now `WIImageResize.lubanV2`. It keeps
ordinary long screenshots more completely while bounding extreme panoramas and
very large pixel counts. To retain WICompress's corrected Luban 1 sizing, select
it explicitly:

```swift
let process = WIImageProcess(
    sizing: .resize(using: WIImageResize.luban)
)
```

Neither algorithm owns quality, output representation, metadata, or target
bytes.

## Output and metadata

Process and Target share `WIImageOutput`, but their defaults are intentionally
different:

- Process preserves the source representation and color semantics, strips
  metadata, and uses quality `0.6` when the format supports lossy quality.
- Target strips metadata, converts rendered output to sRGB, and selects PNG for
  alpha sources or JPEG otherwise.

JPEG output no longer silently flattens transparency. Choose an opaque
background explicitly:

```swift
let output = WIImageOutput(
    representation: .jpeg(background: .white)
)
```

Metadata selection uses `ImageMetadataOptions`, including readable `.strip` and
`.preserve` values and independent Exif, GPS, IPTC, TIFF, and maker-note flags.

## Async overload migration

Every Data/file Process/Target terminal has a same-name async overload:

```swift
let result = try await WICompressor.process(imageData)
let thumbnail = try await WICompressor.compress(imageData, to: target)
```

In an async context, Swift prefers the async overload. A synchronous call from
1.x that previously omitted `await` will therefore stop compiling after the
upgrade; add `await` when asynchronous execution is intended. To deliberately
run the synchronous terminal, call it from a non-async helper or explicitly
bind the synchronous function overload. Omitting `await` inside an async
function does not select the synchronous implementation.

Synchronous overloads keep typed `throws(WICompressError)`. Async overloads use
ordinary `async throws`: processing failures remain `WICompressError`, while
structured-task cancellation remains `CancellationError`. Cancellation is
observed between pipeline stages and Target attempts; an ImageIO or Core
Graphics operation already in progress may finish first.

## Architecture reference

See the [2.0 architecture](../architecture/README.md) for current module and
execution ownership.
