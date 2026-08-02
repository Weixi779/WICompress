# Migrating to WICompress 2.0

Move from the 1.x Options and Policy API to the Process and Target domains.

WICompress 2.0 is an intentional breaking release and requires the Swift 6.2
toolchain. Keep using 1.x when either its API or an older toolchain is required.

## Keep the package and import name

The package, library product, module, and import remain unchanged:

```swift
import WICompress
```

The public terminal namespace is now ``WICompressor``. There is no `.shared`
singleton, deprecated wrapper, or old type alias.

| 1.x | 2.0 |
| --- | --- |
| `WICompress.compress(_:options:)` | `WICompressor.process(_:using:)` |
| `WICompress.compress(contentsOf:options:)` | `WICompressor.process(contentsOf:using:)` |
| `WICompress.compress(_:to:)` | `WICompressor.compress(_:to:)` |
| `WICompress.compress(contentsOf:to:)` | `WICompressor.compress(contentsOf:to:)` |

## Replace Options and Policy

Use ``WIImageProcess`` when the application specifies resize, crop, quality, and
output behavior. Use ``WICompressionTarget`` when the encoded result must satisfy
a hard `maxBytes` contract.

```swift
let result = try WICompressor.process(input, using: process)
let constrained = try WICompressor.compress(input, to: target)
```

Both paths now return ``WIResult``. Code that previously consumed Process `Data`
directly should read `result.data`.

## Migrate Target geometry

The 1.x `WICompressionGeometry` combined soft sizing with hard canvas layout.
In 2.0, ``WICompressionSizing`` describes the starting pixels for byte-target
search, and the search may reduce those dimensions to satisfy `maxBytes`.

| 1.x | 2.0 |
| --- | --- |
| `.original` | `WICompressionSizing.original` |
| `.fit(maxLongSide:)` | `WICompressionSizing(maximumPixelSize:)` |
| `.fitInside(box:)` | No general Target equivalent. Resolve a source-aware longest-side cap, or use Process `WIImageResize.constrained(within:)` when no byte ceiling is required. |
| `.fill(size:crop:)` | Target may use `aspectRatio`, `maximumPixelSize`, and ``WICropAnchor`` as soft constraints. Use Process crop plus `WIImageResize.exact(_:)` for an exact size. |
| `.exactCanvas(size:placement:background:)` | No replacement. Compose canvas padding, placement, and background outside WICompress. |

The old hard `.fill` could upscale and never reduced its requested dimensions;
a 2.0 Target never upscales and may shrink below its base size. Normalized,
top-left-origin
``WICropAnchor`` values replace `WICropMode` only for aspect-ratio crop, not for
canvas alignment. `WIImagePlacement` and `WICompressionPreference` are removed.

`WICompressionOutput` becomes ``WIImageOutput``, while
`WICompressionResult` becomes ``WIResult`` and uses ``ImageFormat`` plus
``WIPixelSize`` for its image facts. The default Target still selects
PNG for alpha or JPEG otherwise and strips metadata, but rendered output now
converts to sRGB instead of preserving the source color space. Preserve the 1.x
default explicitly when required:

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

Construction now validates `maxBytes` and throws ``WICompressError``. The full
mapping, including crop-anchor coordinates and removed output policies, is in
the repository's migration guide.

## Review the default sizing change

The default Process now uses ``WIImageResize/lubanV2``. To retain WICompress's
corrected Luban 1 sizing behavior, select it explicitly:

```swift
let process = WIImageProcess(
    sizing: .resize(using: WIImageResize.luban)
)
```

Neither Luban implementation independently changes output format or quality.

## Migrate same-name async overloads

Data and file Process/Target terminals now have async overloads:

```swift
let result = try await WICompressor.process(input, using: process)
```

Swift prefers the async overload inside an async context. Existing synchronous calls
in async functions must add `await` after upgrading; they do not keep selecting the
synchronous overload. If synchronous execution is intentional, make the call from a
non-async helper or explicitly bind the synchronous function overload.

Synchronous overloads retain typed `throws(WICompressError)`. Async overloads also
preserve `CancellationError`; see <doc:Concurrency-and-Cancellation>.
