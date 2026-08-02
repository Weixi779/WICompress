# Changelog

All notable changes to WICompress will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic
Versioning.

## [2.0.0] - 2026-08-02

WICompress 2.0 replaces the 1.x policy surface with two explicit product
domains: deterministic image processing and byte-target compression.

### Added

- `WICompressor.process(_:using:)` and its file URL terminal with
  `WIImageProcess`.
- Swift 6.2 `@concurrent` async overloads for every Data and file Process/Target
  terminal, with cooperative cancellation between pipeline stages and Target
  search attempts.
- Extensible `WIImageResizing`, built-in `WIImageResize` algorithms, and
  aspect-ratio crop with normalized anchors.
- `WIImageResize.lubanV2`, with mobile-oriented sizing for standard photos,
  panoramas, large-pixel sources, and long images.
- Shared `WIImageOutput` requirements for representation, metadata, and color
  space.
- One `WIResult` from every Process and Target terminal.
- Public `WIImageIO` product with a flat `ImageReader → ImageFrame → encode` API,
  inspection, thumbnail, source transcode, runtime capability, and `ImageIOError`.
- Package-only `WIImageDomain`, `WIImageRendering`, `WICompressDomain`, and
  `WICompressExecution` modules behind the public umbrella and ImageIO product.
- Bilingual architecture and DocC guides for the Domain, ImageIO, Rendering,
  Pipeline, concurrency, and 1.x migration boundaries.
- A reproducible Target compression benchmark with fixed corpora, hard-limit
  validation, quality metrics, environment fingerprints, and offline comparison.

### Changed

- The package and module remain `WICompress`; the public static terminal is now
  the uninhabited `WICompressor` namespace.
- `WICompressionTarget` is now a throwing, immutable `maxBytes` +
  `WICompressionSizing` + `WIImageOutput` contract, with request-scoped
  execution owned directly by `ImagePipeline`.
- Target dimensions are now soft search inputs: an optional aspect-ratio crop
  and longest-side cap establish the base candidate, which may be reduced to
  satisfy `maxBytes`. The 1.x hard fill and exact-canvas contracts are not
  carried forward.
- The default Target output still selects PNG for alpha or JPEG otherwise and
  strips metadata, but rendered output now converts to sRGB instead of
  preserving the source color space.
- Process and Target terminals now return the shared `WIResult`; callers that
  only need encoded bytes read `result.data`, and byte count is derived from the
  data.
- `WICompressionOutput` is replaced by the shared `WIImageOutput`, and binary
  metadata policy is replaced by category-selectable `ImageMetadataOptions`.
- The default Process sizing is now Luban 2. The corrected Luban 1 behavior
  remains available through explicit `WIImageResize.luban`.
- The package requires Swift 6.2 and Xcode 26.
- Async terminals preserve the standard `CancellationError`; synchronous
  terminals retain their typed `throws(WICompressError)` signatures and do not
  observe surrounding task cancellation.
- The SwiftUI example is now a Swift 6 single-screen Process/Target demo with
  request-owned loading, cancellation, and typed ImageIO inspection.
- README is now a focused quick start for the two products, backed by a
  fixture-generated Process/Target comparison image.

### Removed

- The old public `WICompress` facade; 2.0 provides no compatibility alias or
  singleton.
- The 1.x `WICompressOptions` terminal and its resize, format, metadata,
  quality, and color-space policy types.
- `WICompressionGeometry`, including `fitInside`, hard `fill`, and
  `exactCanvas`; `WICropMode`; and `WIImagePlacement`. Normalized crop anchors
  replace only the aspect-ratio crop subset, not canvas layout.
- `WICompressionPreference` and its candidate-ranking modes. Target search now
  has one deterministic ordering.
- `WICompressionOutput` and its presets, `WICompressionResult`, `WIImageFormat`,
  and `WISize`. Use `WIImageOutput`, `WIResult`, `ImageFormat`, and either
  `WIPixelSize` or `WIAspectRatio`.
- `WIOutputColorSpace.preserveIfSupported`; applications can inspect the source
  color space and choose preserve or conversion explicitly.
- The legacy write-plan resolver and encoder adapter.

## [1.4.0] - 2026-07-10

Broadens platform support and adds open-source infrastructure. No public API
changes.

### Added

- Declared support for Mac Catalyst 14+, tvOS 14+, watchOS 7+, and visionOS 1+.
  The core has always been pure ImageIO/CoreGraphics, so no code changes were
  required.
- GitHub Actions CI: build and test on macOS and an iOS Simulator, plus
  build-only verification for tvOS, watchOS, and visionOS.
- DocC documentation catalog and Swift Package Index configuration (`.spi.yml`).
- Requirements and installation section in the README.

### Changed

- `compress(contentsOf:to:)` no longer validates the target twice; behavior is
  unchanged.

## [1.3.0] - 2026-06-28

Adds target-based compression: declare a hard byte ceiling plus output geometry,
and the library searches quality and dimensions to satisfy it. The process-based
`compress(_:options:)` API is unchanged.

### Added

- Target-based compression with `WICompressionTarget`, `WICompressionGeometry`,
  `WICompressionOutput`, `WICompressionPreference`, and `WICompressionResult`.
- Hard byte ceilings through `WICompress.compress(_:to:)` and
  `WICompress.compress(contentsOf:to:)`.
- Canvas-oriented output geometry for fit, fill, crop, and exact-canvas
  workflows.
- Lossy target solving for JPEG and HEIC using quality search and dimension
  reduction.
- Lossless PNG target solving with dimension reduction for soft geometry.

## [1.2.1] - 2026-06-26

Fixes fit resize max-size handling for long screenshots and panoramic images.

### Fixed

- Fixed `WIResizePolicy.fit(minSize:maxSize:)` so `maxSize` is a hard bounding
  box. Images now downscale when either side exceeds `maxSize`, not only when
  both sides exceed it.

## [1.2.0] - 2026-06-26

Adds alpha-aware output selection and range-based resize fitting while keeping
the data-first v1 API compatible.

### Added

- `WIFormatPolicy.pngIfAlphaOtherwiseJPEG`, which writes PNG when the source has
  an alpha channel and JPEG otherwise.
- `WISize` for width/height policy values.
- `WIResizePolicy.fit(minSize:maxSize:)`, which:
  - upscales only when both display sides are below `minSize`;
  - downscales only when both display sides are above `maxSize`;
  - leaves the image unchanged when either side is already in range.
- Redraw support for fit-based upscaling, since ImageIO thumbnail max-size
  options only cover downscaling.
- Swift Testing coverage for alpha-aware format selection and fit resize paths,
  including real ImageIO output dimensions.

### Changed

- The resolver can now carry an exact target pixel size in addition to ImageIO's
  longest-side cap so resize policies can express both downscale and upscale
  outcomes.
- Documentation now describes alpha-aware format selection and range-based fit
  resizing in both English and Simplified Chinese.

## [1.1.0] - 2026-06-22

Adds explicit output control for callers that need a specific upload format or
pixel cap while keeping the v1 data-first API intact.

### Added

- Explicit output format policies:
  - `.format(.jpeg(background:))`
  - `.format(.png)`
  - `.format(.heic)`
- `WIJPEGBackground` with `.disallow`, `.white`, and `.black` for intentional
  transparent-source handling when encoding JPEG.
- `.maxPixel(Int)` resize policy for caller-supplied longest-side caps without
  upscaling smaller images.
- `WICompressError.transparentSourceRequiresBackground` for transparent sources
  encoded as JPEG without an explicit background.

### Changed

- Explicit format conversion always rewrites output instead of returning the
  original data through the size guard.
- JPEG encoding rejects transparent sources by default. Callers must choose
  `.jpeg(background: .white)` or `.jpeg(background: .black)` to flatten alpha.
- Format conversion with `.metadata(.preserve)` re-attaches ordinary metadata
  dictionaries where ImageIO supports them.
- Format conversion still bakes orientation into pixels and resets the
  orientation tag to `1` on the redraw path.

### Known Limitations

- GPS-only metadata stripping is not included.
- Target-byte-size compression is not included.
- Automatic format selection is not included.
- HDR gain-map preservation is not guaranteed.

## [1.0.0] - 2026-06-22

Initial public release of the ImageIO-backed core.

### Added

- Data-first compression APIs for `Data` and file `URL` input.
- UIKit/AppKit-free ImageIO compression pipeline for iOS 14+ and macOS 11+.
- JPEG, PNG, and HEIC/HEIF container detection.
- Luban resize policy based on EXIF-oriented display dimensions.
- Metadata policies for stripping or preserving ordinary image metadata.
- Lossy quality policy for JPEG and HEIC destinations.
- Typed `WICompressError` failure model.
- Swift Testing coverage with real-image fixtures for metadata, orientation,
  alpha, color profile, format detection, and size-guard behavior.
- SwiftUI example app demonstrating PhotosPicker/PHPicker data loading and
  compression preview.

### Changed

- Replaced the old `UIImage`-oriented API from 0.x with a `Data`/`URL` core API.
- Preserved the source container format by default instead of implicitly falling
  back to JPEG.
- Reported failures through `throws(WICompressError)` instead of optional
  results.

### Removed

- Removed `WICompress.resizeImage(_:)`.
- Removed `WICompress.compressImage(_:quality:formatData:)`.

### Known Limitations

- Animated images are rejected.
- Live Photo compression is not supported.
- Async APIs are not included.
- Explicit format conversion policies such as PNG to JPEG are not included.
- Target-byte-size compression is not included.
- HDR gain-map preservation is not guaranteed.
- WebP and JPEG XL writing are not included.

## [0.2.2] - 2024-03-09

Last public 0.x release before the ImageIO-backed API redesign.
