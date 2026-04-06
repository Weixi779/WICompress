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
| `.compression` | UIKit compression and resize behavior (`WICompress` public API) |
| `.edgeCase` | Boundary values and edge inputs |

Tag definitions live in `Tests/WICompressTests/Support/Tags.swift`.

### Running Tests

**Pure logic (macOS, no simulator needed):**
```bash
swift test
```

**Full suite including compression tests (iOS Simulator required):**
```bash
xcodebuild test \
  -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme WICompress \
  -destination 'platform=iOS Simulator,OS=18.4,name=iPhone 16 Pro Max' \
  CODE_SIGNING_ALLOWED=NO
```

> `CODE_SIGNING_ALLOWED=NO` is required — without it, xcodebuild fails with a CodeSign error when testing SPM packages directly.

### Test Categories

**macOS (`swift test`)** — pure logic, no UIKit:
- `LubanRatioTests` — parameterized tests covering all 7 Luban switch branches + `ensureEven` edge cases
- `WIImageFormatTests` — format detection using CGContext-generated images (JPEG, PNG, unknown)

**iOS Simulator (`xcodebuild`)** — UIKit-dependent, wrapped in `#if os(iOS)`:
- `CompressionTests` — validates `compressImage` output (non-nil, size reduction, format preservation, quality effect) and `resizeImage` dimension behavior

### Test Resources

`Tests/WICompressTests/Resources/` is registered in `Package.swift` for future real-image assets. Load via `Bundle.module.url(forResource:withExtension:)` in tests.