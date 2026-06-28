# WICompress Roadmap Notes

This document captures future design discussion. It is not part of any release
contract.

## Target-Based Compression

Shipped in 1.3.0 as `WICompress.compress(_:to:)` with `WICompressionTarget`; see
the Target Compression section of the README for usage. Remaining follow-ups:

- Whether to expose diagnostics for why a target result was returned: original
  passthrough, quality search, dimension reduction, metadata rewrite, format
  conversion, or fallback.
- Whether PNG target compression should add an optional refinement pass between
  the last too-large size and the first fitting size.
- Whether future lossy PNG behavior, such as palette quantization, should be
  modeled as a separate explicit policy.

## Metadata Control

The current metadata policy is intentionally coarse: strip ordinary privacy-heavy
metadata or preserve it. Future versions may need a more expressive policy that
states which metadata families are allowed to survive.

Likely direction:

- Keep color profile handling out of metadata policy. Color profiles are display
  semantics and should be owned by output color-space control.
- Add a GPS-only stripping mode as a focused privacy improvement.
- Consider an allow/deny style policy for metadata families such as GPS, Exif,
  TIFF, IPTC, maker notes, and orientation.
- Keep orientation special: redraw paths bake it into pixels and reset the tag to
  `1`; preserving a stale orientation tag would be incorrect.

Open API sketch:

```swift
public enum WIMetadataPolicy: Sendable, Equatable {
    case strip
    case preserve
    case stripLocation
    case custom(WIMetadataRules)
}

public struct WIMetadataRules: Sendable, Equatable {
    public var gps: WIMetadataRule
    public var exif: WIMetadataRule
    public var tiff: WIMetadataRule
    public var iptc: WIMetadataRule
    public var makerNotes: WIMetadataRule
}

public enum WIMetadataRule: Sendable, Equatable {
    case preserve
    case strip
}
```

## Photos Adapter

The core should stay UIKit/AppKit-free and keep accepting `Data` or file `URL`.
Convenience integration with Apple's photo-picking APIs belongs in an adapter
layer so the core package remains usable on macOS and in non-UI contexts.

Likely direction:

- Add a separate Photos-facing module or companion target instead of importing
  Photos/PhotosUI in the core target.
- Support picker-driven workflows that can provide original image data without
  broad photo-library access where Apple's APIs allow it.
- Treat `PHAsset` support carefully: `PHAsset` itself is Photos-framework state,
  and exact permission behavior depends on the API path. Verify the current Apple
  contract before designing the public surface.
- The adapter should resolve the selected asset or picker item to original image
  bytes, then pass those bytes into the existing ImageIO pipeline.
- Avoid returning `UIImage`/`NSImage` as the primary API shape; those should stay
  UI-boundary preview types.

Possible module shape:

```swift
// Separate target, not the core WICompress target.
import WICompress
import Photos
import PhotosUI

public enum WIPhotoAssetReader {
    public static func imageData(for asset: PHAsset) async throws -> Data
}
```

## Algorithm And Architecture Expansion

Longer-term work can revisit the strategy boundaries once the v1 API surface is
stable.

Possible directions:

- Documentation examples for composing application-owned targets. WICompress
  should not ship platform-specific sharing presets; applications should define
  targets from the current SDK documentation they integrate with.
- Strategy protocols for resize, target bytes, metadata handling, and encoding
  so each feature can evolve without making the resolver monolithic.
- More fixture-driven characterization tests for edge formats such as uncommon
  ICC profiles, HDR sources, and server-oriented upload limits.
- Better diagnostics for why a result was returned: original passthrough, quality
  search, dimension reduction, metadata rewrite, format conversion, or fallback.
