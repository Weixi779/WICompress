# Changelog

All notable changes to WICompress will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic
Versioning.

## [Unreleased]

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
