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

Uses Swift Testing framework (not XCTest) - tests are located in `Tests/WICompressTests/`