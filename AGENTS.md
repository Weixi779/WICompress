# AGENTS.md

This file is the single source of truth for coding-agent guidance in this
repository. Other agent-specific entry files should point here instead of
duplicating the same instructions.

## Project Overview

WICompress is a lightweight ImageIO-based image compression library for JPEG,
PNG, and HEIC/HEIF data. It uses the Luban resize strategy, preserves the source
container format by default, and exposes a UIKit/AppKit-free core API. The
package targets iOS 14+ and macOS 11+.

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

The core is a UIKit-free ImageIO pipeline under `Sources/WICompress/Core/`. The
public entry point is `Data`/`URL` in, `Data` out:

```text
Data / URL
  -> WIImageSource (Inspect)        decode source, read WIImageInfo (no UIKit)
  -> WIWritePlanResolver            map (options, info) -> WIWritePlan + write path
  -> WIImageEncoder (Execute)       run the chosen write path
  -> size guard                     return original if re-encode did not help and policy allows
  -> Data
```

Key types:

1. **WICompress** - public API: `compress(_:options:) throws(WICompressError) -> Data`
   and `compress(contentsOf:options:)`.
2. **WICompressOptions** - `resize` / `format` / `metadata` / `quality` policies
   (see `WIResizePolicy`, `WIFormatPolicy`, `WIMetadataPolicy`, `WIQualityPolicy`).
3. **WIImageSource** / **WIImageInfo** - ImageIO source wrapper and inspected facts
   (format, pixel size, orientation, frame count, alpha, gain map, writability).
4. **WIWritePlanResolver** / **WIWritePlan** - the decision core. Picks one of
   `returnOriginal` / `copyFromSource` / `redrawBitmap`.
5. **WIImageEncoder** - executes the plan via `CGImageDestination`.
6. **WIImageFormat** - `UTType`-based container detection (JPEG/PNG/HEIF/unknown).
7. **WIImageUtils** - Luban ratio math (`calculateLubanRatio`, `ensureEven`).
8. **WICompressError** - strongly typed error (`LocalizedError`); the only thrown type.

## Key Implementation Details

- **Two ImageIO write paths**: `copyFromSource` preserves metadata/orientation
  tags and is used for `.metadata(.preserve)`. `redrawBitmap` downsamples via
  `CGImageSourceCreateThumbnailAtIndex` with transform, bakes orientation, and
  resets the tag to 1; it is used for the default `.strip` upload path.
- **UIKit-free / cross-platform core**: no `#if os(iOS)`, no UIKit/CoreImage.
  Builds and is fully tested on macOS via `swift test`.
- **Typed throws**: the whole throwing surface uses `throws(WICompressError)`.
  Builds cleanly under Swift 6 language mode and strict concurrency; public
  types are `Sendable`.
- **Luban resize**: ratio is computed from EXIF-oriented display dimensions. The
  default long-image branch constrains the short side (`ceil(shortSide / 1280)`),
  matching original Luban. Dividing the long side over-shrinks panoramas and
  long screenshots.
- **Format/quality coupling**: quality is only written for lossy destinations
  (JPEG/HEIC). PNG ignores it. Writability is checked at runtime via
  `CGImageDestinationCopyTypeIdentifiers()`.
- **Size guard**: never returns the original if it would violate a policy, for
  example `.strip` must not hand back a GPS-bearing original.
- **Error handling**: throws `WICompressError`, never returns optional/nil.

## Testing Framework

Uses Swift Testing framework, not XCTest. Tests are located in
`Tests/WICompressTests/`.

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

The core is UIKit-free, so the entire suite runs on `swift test` on macOS,
including the real-image fixture tests. This is the fastest daily gate:

```bash
swift test
```

Keep an iOS Simulator package test as the platform behavior gate before commits
that touch the core, fixtures, Package manifest, or public API. Do not hardcode
simulator names or OS versions; discover devices first and use the UDID:

```bash
xcrun simctl list devices available
xcodebuild test \
  -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme WICompress-Package \
  -destination 'id=<UDID>' \
  CODE_SIGNING_ALLOWED=NO
```

If the scheme changes, inspect it instead of guessing:

```bash
xcodebuild -list -workspace .swiftpm/xcode/package.xcworkspace
```

`CODE_SIGNING_ALLOWED=NO` is required when testing SPM packages directly through
`xcodebuild` to avoid CodeSign failures.

For the example app, use a generic simulator build destination:

```bash
xcodebuild build \
  -project Example/WICompressExample/WICompressExample.xcodeproj \
  -scheme WICompressExample \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

### Test Categories

All suites run under `swift test` on macOS; none depend on UIKit:

- `LubanRatioTests` - Luban switch branches and `ensureEven` edge cases
- `WIImageFormatTests` - `UTType`-based format detection (JPEG, PNG, unknown)
- `WICompressPublicSurfaceTests` - default options, no-op passthrough, error mapping
- `WICompressImageIOCoreTests` - write-path behavior on real fixtures: GPS strip
  vs preserve, orientation baking, PNG alpha, gain-map drop in `.preserve`,
  animated rejection, size-guard correctness
- `WICompressDataCharacterizationTests` - auto-discovers `Resources/` images and
  pins the format + display-dimension contract

### Test Resources

`Tests/WICompressTests/Resources/` is registered in `Package.swift` for real
image assets. Load fixtures via `Bundle.module.url(forResource:withExtension:)`
in tests.
