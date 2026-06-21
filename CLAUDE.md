# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WICompress is a lightweight iOS image compression library that supports JPEG, PNG, and HEIC formats using the Luban algorithm for intelligent compression. It's implemented as a Swift Package Manager library targeting iOS 14+.

## Development Commands

### Building
```bash
swift build
```

### Testing
```bash
swift test
```

### Package Resolution
```bash
swift package resolve
```

## Architecture

The library consists of three main components:

1. **WICompress.swift** - Main public API providing static methods for image compression
   - `resizeImage(_:)` - Resizes images using Luban algorithm
   - `compressImage(_:quality:formatData:)` - Compresses images with quality control

2. **WIImageProcessor.swift** - Core image processing implementation
   - Handles resize operations by ratio or target size
   - Manages format-specific compression (JPEG, PNG, HEIC)
   - Contains HEIC conversion using CGImageDestination

3. **WIImageFormat.swift** - Image format detection and enumeration
   - Automatically detects format from Data using UTType
   - Supports JPEG, PNG, HEIF/HEIC, and unknown formats

## Key Implementation Details

- **Luban Algorithm**: Calculates optimal compression ratios based on aspect ratio and dimensions
- **iOS-only**: Code is wrapped in `#if os(iOS)` conditionals
- **HEIC Support**: Uses CGImageDestination for HEIC compression with quality control
- **Format Detection**: Relies on UTType and CGImageSource for automatic format detection
- **Error Handling**: Returns optional values (nil) when operations fail

## Testing Framework

Uses Swift Testing framework (not XCTest). Tests are located in `Tests/WICompressTests/`.

### Test Organization

Tests are organized by `@Suite` and filtered by `@Tag`:

| Tag | Scope |
|---|---|
| `.luban` | Luban algorithm logic (`calculateLubanRatio`, `ensureEven`) |
| `.format` | Image format detection (`WIImageFormat`) |
| `.compression` | Compression and resize behavior (`WICompress` public API) |
| `.imageIOCore` | ImageIO core: write-path resolution, encoder, real-image contracts |
| `.publicAPI` | Public surface: options defaults, error mapping, entry points |
| `.edgeCase` | Boundary values and edge inputs |

Tag definitions live in `Tests/WICompressTests/Support/Tags.swift`.

### Running Tests

The core is UIKit-free, so **the entire suite runs on `swift test` (macOS, no
simulator needed)** — including the real-image fixture tests:
```bash
swift test
```

> An iOS Simulator is no longer required to test the library. `xcodebuild`/the
> simulator is only relevant for building the `Example/` app, not the package
> tests. If you do run the package under `xcodebuild` for SPM packages directly,
> pass `CODE_SIGNING_ALLOWED=NO` (otherwise it fails with a CodeSign error).

### Test Categories

All suites run under `swift test` on macOS — none depend on UIKit:
- `LubanRatioTests` — all 7 Luban switch branches + `ensureEven` edge cases
- `WIImageFormatTests` — `UTType`-based format detection (JPEG, PNG, unknown)
- `WICompressPublicSurfaceTests` — default options, no-op passthrough, error mapping
- `WICompressImageIOCoreTests` — write-path behavior on real fixtures: GPS strip vs preserve, orientation baking, PNG alpha, gain-map drop in `.preserve`, animated rejection, size-guard correctness
- `WICompressDataCharacterizationTests` — auto-discovers `Resources/` images and pins the format + display-dimension contract

### Test Resources

`Tests/WICompressTests/Resources/` is registered in `Package.swift` for future real-image assets. Load via `Bundle.module.url(forResource:withExtension:)` in tests.