# AGENTS.md

This file is the single source of truth for coding-agent guidance in this
repository. Other agent-specific entry files should point here instead of
duplicating the same instructions.

## Project Overview

WICompress is a lightweight ImageIO-based image compression library for JPEG,
PNG, and HEIC/HEIF data. It uses the Luban resize strategy, preserves the source
container format by default, supports explicit JPEG/PNG/HEIC output control, and
exposes a UIKit/AppKit-free core API. The package targets iOS 14+ and macOS 11+.

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

## Repository Layout

Use capitalized names for Swift/package roots (`Sources`, `Tests`, `Example`)
and lowercase names for auxiliary repository directories (`docs`, `scripts`).

## CodeGraph

This repository is initialized for CodeGraph. The `.codegraph/` directory is a
local index and is ignored by git.

Use CodeGraph for structural questions:

| Question | Tool |
|---|---|
| Where is a symbol defined? | `codegraph_search` |
| What calls a symbol? | `codegraph_callers` |
| What does a symbol call? | `codegraph_callees` |
| How does one symbol reach another? | `codegraph_trace` |
| What changes if this symbol changes? | `codegraph_impact` |
| Show symbol signature/source/context | `codegraph_node`, `codegraph_context`, `codegraph_explore` |
| What files exist under a path? | `codegraph_files` |

Prefer `codegraph_context` first for architecture, feature, or bug-context
questions. Prefer `codegraph_trace` for flow questions. Use `rg` for literal
text, comments, log messages, or string contents. If CodeGraph reports pending
sync for edited files, read those specific files directly before relying on the
stale snippets.

## Architecture

The core is a UIKit-free ImageIO pipeline under `Sources/WICompress/`, grouped
by role:

```text
Sources/WICompress/
  WICompress.swift
  Model/
  Policies/
  Pipeline/
  Algorithm/
```

The public entry point is `Data`/`URL` in, `Data` out:

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
   (see `WIResizePolicy`, `WIFormatPolicy`, `WIJPEGBackground`,
   `WIMetadataPolicy`, `WIQualityPolicy`).
3. **WIImageSource** / **WIImageInfo** - ImageIO source wrapper and inspected facts
   (format, pixel size, orientation, frame count, alpha, gain map, writability).
4. **WIWritePlanResolver** / **WIWritePlan** - the decision core. Picks one of
   `returnOriginal` / `copyFromSource` / `redrawBitmap`.
5. **WIImageEncoder** - executes the plan via `CGImageDestination`.
6. **WIImageFormat** - `UTType`-based container detection (JPEG/PNG/HEIF/unknown).
7. **WILuban** - internal Luban ratio math (`ratio(width:height:)`, `ensureEven`).
8. **WICompressError** - strongly typed error (`LocalizedError`); the only thrown type.

## Key Implementation Details

- **Two ImageIO write paths**: `copyFromSource` preserves metadata/orientation
  tags and is used for `.metadata(.preserve)`. `redrawBitmap` downsamples via
  `CGImageSourceCreateThumbnailAtIndex` with transform, bakes orientation, and
  resets the tag to 1; it is used for the default `.strip` upload path.
- **Explicit format conversion**: `.format(.jpeg/.png/.heic)` always uses
  `redrawBitmap` and never returns the original through the size guard. JPEG
  conversion rejects transparent sources by default; callers must choose
  `.jpeg(background: .white/.black)` to flatten alpha intentionally.
- **UIKit-free / cross-platform core**: no `#if os(iOS)`, no UIKit/CoreImage.
  Builds and is fully tested on macOS via `swift test`.
- **Typed throws**: the whole throwing surface uses `throws(WICompressError)`.
  Builds cleanly under Swift 6 language mode and strict concurrency; public
  types are `Sendable`.
- **Resize policies**: Luban ratio is computed from EXIF-oriented display
  dimensions. The default long-image branch constrains the short side
  (`ceil(shortSide / 1280)`), matching original Luban. Dividing the long side
  over-shrinks panoramas and long screenshots. `.maxPixel(Int)` caps the longest
  display side and never upscales.
- **Format/quality coupling**: quality is only written for lossy destinations
  (JPEG/HEIC). PNG ignores it. Writability is checked at runtime via
  `CGImageDestinationCopyTypeIdentifiers()`.
- **Size guard**: never returns the original if it would violate a policy, for
  example `.strip` must not hand back a GPS-bearing original, and explicit
  destination formats must not hand back source-format bytes.
- **Error handling**: throws `WICompressError`, never returns optional/nil.

## Code Style

Comments are minimalist:

- Start Swift source files with the standard repository header:
  filename, code scope, `Created by weixi on YYYY/M/D.`, and a one-line
  copyright + Apache-2.0 license notice. Skip this header in `Package.swift`,
  where `// swift-tools-version` must stay first. Use this shape:

  ```swift
  //
  //  SomeFile.swift
  //  WICompress
  //
  //  Created by weixi on 2026/6/22.
  //  Copyright © 2024 weixi. Licensed under Apache-2.0.
  //
  ```

- Document public API with a single-sentence `///` summary. Skip it when the
  signature is already self-explanatory.
- Do not add `- Parameter` / `- Returns` / `- Throws` boilerplate unless it states
  something the signature does not.
- Comment the non-obvious *why* (rationale, platform quirks, gotchas), never the
  *what*. If a comment just restates the code, delete it or rename the code.
- No decorative ASCII banners, extra dates, or changelog comments in source.
- Prefer a clearer name over a comment.

## Testing Framework

Uses Swift Testing framework, not XCTest. Tests are located in
`Tests/WICompressTests/`.

### Test Organization

Tests are organized by `@Suite` and filtered by `@Tag`:

| Tag | Scope |
|---|---|
| `.luban` | Luban algorithm logic (`WILuban.ratio`, `WILuban.ensureEven`) |
| `.format` | Image format detection (`WIImageFormat`) |
| `.compression` | Compression and resize behavior (`WICompress` public API) |
| `.imageIOCore` | ImageIO core: write-path resolution, encoder, real-image contracts |
| `.publicAPI` | Public surface: options defaults, error mapping, entry points |
| `.edgeCase` | Boundary values and edge inputs |
| `.algorithm` | Pure target-search math (`WICompressionSizeEstimation`, `WICompressionRanking`) |

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

- `LubanRatioTests` - Luban switch branches and `WILuban.ensureEven` edge cases
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
