# Changelog

All notable changes to WICompress will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic
Versioning.

## [Unreleased]

### Added

- `WICompressionTarget` for result-constrained compression with `maxBytes`,
  optional `maxLongSide`, output format, and metadata policy.
- `WICompress.compress(_:to:)` and `WICompress.compress(contentsOf:to:)` target
  compression APIs.
- Target compression solver that searches dimensions and lossy quality for
  JPEG/HEIC while keeping PNG output in PNG and shrinking dimensions only.
- `WICompressError.invalidCompressionTarget` for invalid target limits.
- `WICompressError.targetBytesUnreachable` when no encoded output can satisfy
  the requested byte limit and output constraints.

### Changed

- The documented current limits no longer list target-byte-size compression as
  unsupported.

### Known Limitations

- Target compression does not perform PNG palette quantization.
- Target compression does not silently switch formats to satisfy `maxBytes`.

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

## [1.0.0] - TBD

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
