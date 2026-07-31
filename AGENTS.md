# AGENTS.md

This file is the single source of truth for coding-agent guidance in this
repository. Other agent-specific entry files should point here instead of
duplicating the same instructions.

## Project Overview

WICompress is a lightweight ImageIO-based image compression library for JPEG,
PNG, and HEIC/HEIF data. It uses the Luban resize strategy, preserves the source
container format by default, supports explicit JPEG/PNG/HEIC output control, and
exposes a UIKit/AppKit-free core API. The package targets iOS 14+, macOS 11+,
Mac Catalyst 14+, tvOS 14+, watchOS 7+, and visionOS 1+.

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

### Continuous Integration

GitHub Actions (`.github/workflows/ci.yml`) runs on every push to `main` and on
pull requests: `swift build` + `swift test` on macOS, the package test suite on
an iOS Simulator, and build-only jobs for tvOS/watchOS/visionOS simulators.

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

The package is split into four supporting targets and one public umbrella
product target:

```text
             WIImageDomain
               ↑       ↑
       WIImageIO       WIImageRaster
               ↑       ↑
           WICompressExecution
                   ↑
               WICompress
```

`WIImageDomain` owns the public Process, Target, Output, pixel-size, and color
values used directly by package execution. Package-only validation, `Rect`, and
`Orientation` live beside those values; there are no mirrored Core models.
`WIImageIO` owns the public result fact `WIImageFormat` and all package-only
ImageIO primitives. `WICompressExecution` owns the request-scoped
`ImagePipeline`, pure Process/Target calculations, `WICompressError`, and
`WIResult`. `WICompress` re-exports the public contracts and contains only
`WICompressor`, whose terminals call the package-only `ImagePipeline` directly.

Process is the deterministic `Data`/`URL` in, `WIResult` out path:

```text
Data / URL + WIImageProcess
  -> ImagePipeline
       validate source-independent Process facts before source creation
       inspect source
       crop -> WIImageResizing -> concrete geometry
       resolve output and choose return-original / source-copy / render
       no crop shrink -> two-axis-safe ImageIO thumbnail
       axis upscaling -> full source
       crop -> oriented source + WIImageRaster
       encode -> WIImageIO
       encoded Data -> result inspection -> WIResult
```

The Process file terminal keeps a file-backed ImageIO source. It reads the
complete original bytes only when a return-original operation needs them.

Target-based `compress(_:to:)` declares an output contract (`maxBytes` plus
sizing/output) and returns a `WIResult`:

```text
Data / URL + WICompressionTarget
  -> ImagePipeline
       validate source-independent target facts before source creation
       inspect source and resolve fixed crop/base size/output
       passthrough when the original already satisfies every requirement
       otherwise run feedback search: shrink (outer) + quality (inner)
       reuse one rendered image while searching quality at fixed geometry
       use Algorithm/ math for size estimation and candidate ranking
       hard byte check: never return data above maxBytes
       encoded Data -> result inspection -> WIResult
```

Key types:

1. **WICompressor** - public Process `process(_:using:)` and Target
   `compress(_:to:)` terminals for `Data` and file `URL`.
2. **WIImageProcess** - immutable forward-processing description with sizing,
   optional aspect-ratio crop, fixed lossy quality, and `WIImageOutput`.
3. **WIImageResizing** / **WIImageResize** - complete pixel-size decision slot
   and built-in Luban, boundary, scale, and exact-size implementations.
4. **WIImageOutput** - shared representation, composable
   `WIImageMetadataOptions`, and color-space requirements used by both Process
   and Target.
5. **ImagePipeline** - request-scoped owner of the encoded input,
   `WIImageIO.Source`, `Descriptor`, original-byte lifecycle, and
   Process/Target decisions, Target candidate search, and ImageIO/Raster
   execution. Its package terminals are called directly by `WICompressor`;
   there is no second terminal forwarding type.
6. **WIImageFormat** - public ImageIO-produced result fact
   (JPEG/PNG/HEIF/unknown); callers do not initialize it from arbitrary data.
7. **WILuban** - internal Luban ratio math (`ratio(width:height:)`, `ensureEven`).
8. **WICompressError** - strongly typed error (`LocalizedError`); the only thrown type.
9. **Target compression** - `compress(_:to:)` with `WICompressionTarget`
   (`maxBytes` / `WICompressionSizing` / shared `WIImageOutput`) returning
   `WIResult`. `ImagePipeline` validates the target, owns passthrough and the
   byte-budget feedback search, and performs the final hard-limit check.
   Pure math lives in `Algorithm/`: Process/Target geometry (fixed crop + base
   candidate), `WICompressionSizeEstimation` (shrink + quality
   profile), and `WICompressionRanking` (internal deterministic candidate
   selection).

## Key Implementation Details

- **Resolved operations**: `copyFromSource` preserves metadata/orientation tags
  and can remove location metadata without decoding pixels;
  `render` bakes orientation, crop, sizing, color conversion, and backgrounds
  into pixels; `returnOriginal` is used only when every observable requirement
  already holds.
- **Explicit format conversion**: JPEG/PNG/HEIC output always rewrites the
  image. JPEG conversion rejects transparent sources by default; callers choose
  `.jpeg(background: .white/.black)` to flatten alpha intentionally.
- **UIKit-free / cross-platform core**: no `#if os(iOS)`, no UIKit/CoreImage.
  Builds and is fully tested on macOS via `swift test`.
- **Typed throws**: the whole throwing surface uses `throws(WICompressError)`.
  Builds cleanly under Swift 6 language mode and strict concurrency; public
  types are `Sendable`.
- **Image resizing**: Luban ratio is computed from EXIF-oriented display
  dimensions. The default long-image branch constrains the short side
  (`ceil(shortSide / 1280)`), matching original Luban. Dividing the long side
  over-shrinks panoramas and long screenshots. `maximumPixelSize(_:)` caps the
  longest display side and never upscales.
- **Format/quality coupling**: quality is only written for lossy destinations
  (JPEG/HEIC). PNG ignores it. Writability is checked at runtime via
  `CGImageDestinationCopyTypeIdentifiers()`.
- **Passthrough**: never returns the original if it would violate Process or
  Target output requirements.
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
| `.compression` | Process and Target behavior (`WICompressor` public API) |
| `.imageIOCore` | ImageIO core: execution resolution, encoder, real-image contracts |
| `.publicAPI` | Public surface: defaults, error mapping, entry points |
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
  -scheme WICompress-Package \
  -destination 'id=<UDID>' \
  CODE_SIGNING_ALLOWED=NO
```

Run `xcodebuild` from the package root; it resolves SPM packages directly, so no
`-workspace` argument is needed (`.swiftpm/` is untracked local state). If the
scheme changes, inspect it instead of guessing:

```bash
xcodebuild -list
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
- `WICompressorPublicSurfaceTests` - defaults, passthrough, and error mapping
- `WICompressImageIOCoreTests` - write-path behavior on real fixtures: GPS strip
  vs preserve, orientation baking, PNG alpha, gain-map drop in `.preserve`,
  animated rejection, size-guard correctness
- `WICompressDataCharacterizationTests` - auto-discovers `Resources/` images and
  pins the format + display-dimension contract

### Test Resources

`Tests/WICompressTests/Resources/` is registered in `Package.swift` for real
image assets. Load fixtures via `Bundle.module.url(forResource:withExtension:)`
in tests.
