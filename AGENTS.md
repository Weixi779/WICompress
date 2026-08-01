# AGENTS.md

This file is the single source of truth for coding-agent guidance in this
repository. Keep execution constraints here; keep evolving design rationale and
complete architecture documentation under `docs/`.

## Project

WICompress is a Swift 6.2 ImageIO-based image processing and compression
package. It publishes the high-level `WICompress` product and the lower-level
`WIImageIO` product. The core is UIKit/AppKit-free and supports iOS 14+, macOS
11+, Mac Catalyst 14+, tvOS 14+, watchOS 7+, and visionOS 1+.

## Commands

```bash
swift build
swift test
swift package resolve
```

GitHub Actions runs macOS build/tests, iOS Simulator package tests, and
build-only gates for the remaining supported Apple platforms.

## Repository Layout

Use capitalized names for Swift/package roots (`Sources`, `Tests`, `Example`)
and lowercase names for auxiliary directories (`docs`, `scripts`). The public
umbrella keeps its branded `Sources/WICompress` path. Supporting source paths
are grouped by product context and mapped to target names in `Package.swift`:

```text
Sources/image/domain       -> WIImageDomain
Sources/image/io           -> WIImageIO
Sources/image/raster       -> WIImageRaster
Sources/compress/domain    -> WICompressDomain
Sources/compress/execution -> WICompressExecution
Sources/WICompress         -> WICompress
```

Nested organizational directories are lowercase. Target names are the module
identity; physical paths do not repeat the `WI` brand.

## Architecture Boundaries

```text
                    WIImageDomain
                  ↑       ↑       ↑
         WIImageIO  WIImageRaster  WICompressDomain
                  ↖      ↑      ↗
                WICompressExecution
                         ↑
                     WICompress
```

- `WIImageDomain` owns shared image vocabulary and no execution lifecycle.
- `WIImageIO` owns synchronous inspection, decode, transcode, and encode. It
  re-exports canonical Image Domain values instead of defining aliases.
- `WIImageRaster` owns package-only pixel rendering primitives until a public
  Raster API is explicitly designed.
- `WICompressDomain` owns public Process, Target, Output, Result, and compression
  error contracts.
- `WICompressExecution` owns the request-scoped `ImagePipeline`, calculations,
  and lower-level error mapping. It publishes no product models.
- `WICompress` is the public umbrella and terminal surface.

Keep dependencies one-way. Do not introduce mirrored Core models, global
registries, public Pipeline stages, or a second execution owner. `ImagePipeline`
is internal orchestration; pure helpers receive only the values they need.

Current V2 decisions live in `docs/V2_*`. Update the relevant decision document
when a frozen contract changes. Do not duplicate complete Process/Target flows
or algorithm details in this file; a consolidated architecture document will
replace the evolving design set after the refactor is complete.

## Code Style

Start Swift source files with this header. Skip it in `Package.swift`, where the
Swift tools version must remain first.

```swift
//
//  SomeFile.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//
```

- Document public API with a concise `///` summary when the signature does not
  already explain itself.
- Avoid `- Parameter`, `- Returns`, and `- Throws` boilerplate unless it adds
  information absent from the signature.
- Comment the non-obvious reason, platform quirk, or invariant. Never restate
  the code; prefer a clearer name.
- Do not add decorative banners, changelog comments, or extra source dates.
- Prefer immutable public configuration values and construction-time
  normalization when invalid numeric states do not need to interrupt execution.

### Line Wrapping

- Treat 100 characters as a soft limit and 120 as a hard limit. Long indivisible
  strings may exceed it.
- Keep a complete declaration, call, or other semantic unit on one line when it
  fits and remains readable. Do not wrap merely because it has parameters.
- Keep single-argument calls on one line unless the argument is itself multiline
  or a closure.
- When a declaration or call must wrap, put one parameter or argument per line
  and place the closing delimiter consistently on its own line.
- Keep short ternary expressions on one line. Prefer Swift `if`/`switch`
  expressions when a branch requires multiline formatting.
- Break fluent transformations before the leading dot when the chain communicates
  distinct steps.

## Testing

Tests use Swift Testing, not XCTest. Keep tests with the target they validate and
load package fixtures through `Bundle.module`.

The daily macOS gate is:

```bash
swift test -Xswiftc -warnings-as-errors
```

Before commits that touch core behavior, fixtures, `Package.swift`, or public
API, discover an available simulator and run the package gate by UDID:

```bash
xcrun simctl list devices available
xcodebuild test \
  -scheme WICompress-Package \
  -destination 'id=<UDID>' \
  CODE_SIGNING_ALLOWED=NO
```

Do not hardcode simulator names, OS versions, or UDIDs. Run `xcodebuild` from the
package root and inspect `xcodebuild -list` if the scheme changes.

When public API or package integration changes, also build the example:

```bash
xcodebuild build \
  -project Example/WICompressExample/WICompressExample.xcodeproj \
  -scheme WICompressExample \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```
