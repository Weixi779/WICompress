# Contributing to WICompress

Thanks for your interest in improving WICompress! Issues and pull requests are
welcome.

## Getting Started

WICompress is a pure SwiftPM package. Clone the repository and run the test
suite; everything, including the real-image fixture tests, runs on macOS:

```bash
swift build
swift test
```

## Before Opening a Pull Request

- Run `swift test` and make sure the whole suite passes.
- For changes that touch the core pipeline, fixtures, `Package.swift`, or the
  public API, also run the package tests on an iOS Simulator (see
  [AGENTS.md](AGENTS.md) for the exact commands).
- Follow the code style described in [AGENTS.md](AGENTS.md): minimalist
  comments, standard file headers, and a single-sentence `///` summary on
  public API.
- Add or update tests for behavior changes. Tests use the Swift Testing
  framework (not XCTest) and are organized by `@Suite` and `@Tag`.
- Update `CHANGELOG.md` under an Unreleased-style entry when a change is
  user-visible.

## Scope

The library intentionally keeps a small, UIKit/AppKit-free ImageIO core. Before
building a large feature (for example animated output, WebP writing, or
platform-specific presets), please open an issue first so we can discuss
whether it fits — see the Current Limits section of the README for
deliberately excluded features.

## Reporting Bugs

Please include:

- the input image (or its format, pixel size, and source, if it cannot be
  shared)
- the exact `WIImageProcess` or `WICompressionTarget` used
- the thrown `WICompressError` or the unexpected output
- platform and OS version

CI runs `swift build` and `swift test` on macOS, the test suite on an iOS
Simulator, and build checks for Mac Catalyst, tvOS, watchOS, and visionOS on
every pull request.
