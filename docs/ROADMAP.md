# WICompress Roadmap Notes

This document captures future design discussion. It is not part of the v1.1.0
release contract.

## Target Byte Size

Some upload paths need a hard output-size ceiling, for example "the final image
must be under 2 MB." This is a different contract from Luban. Luban is a fast,
one-pass visual-size heuristic; target-bytes compression is an iterative search
that trades CPU time for a stronger byte-size guarantee.

Likely direction:

- Add a target-byte policy that composes with explicit output format control.
- Prefer quality search first for lossy destinations such as JPEG and HEIC.
- Reduce dimensions when quality search cannot satisfy the target or when the
  destination format has no lossy quality knob.
- Keep upper bounds on attempts, minimum dimensions, and quality floors so the
  API fails predictably instead of looping forever or producing unusable output.
- Keep Luban as the default upload heuristic; target bytes should be opt-in
  because it is slower and less visually predictable.

Open API sketch:

```swift
public enum WITargetBytesPolicy: Sendable, Equatable {
    case none
    case max(Int)
}
```

Open design questions:

- Whether target bytes belongs inside `WICompressOptions` directly or inside a
  higher-level preset.
- Whether failure should throw when the target cannot be reached above minimum
  quality/dimensions, or return the smallest acceptable attempt with diagnostics.
- Whether the dimension search should be binary search on longest side, repeated
  halving, or a hybrid that starts from the already-resolved resize policy.

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

## Output Color-Space Control

Color-space handling should be designed together with custom JPEG background
colors. The two concerns are separate in the public API, but they meet in the
encoder: transparent pixels are composited into the resolved output color space.

Likely direction:

- Keep the default behavior conservative and preserve normal source color
  semantics.
- Provide explicit conversion targets for common output spaces such as sRGB and
  Display P3.
- Provide an upload/share compatibility policy that preserves supported spaces
  such as sRGB and Display P3, otherwise converts unusual sources such as CMYK
  to sRGB.
- Let custom JPEG background colors carry their own color space.
- Provide an ICC-profile extension point instead of trying to enumerate every
  professional or display-specific color space.

Open API sketch:

```swift
public enum WIColorSpace: Sendable, Hashable {
    case sRGB
    case displayP3
    case iccProfile(Data)
}

public enum WIOutputColorSpace: Sendable, Equatable {
    case preserve
    case convert(to: WIColorSpace)
    case preserveIfSupported(Set<WIColorSpace>, otherwise: WIColorSpace)
}

public struct WIColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var colorSpace: WIColorSpace
}
```

This area should ship as a dedicated feature version with CMYK and custom
background fixtures, not as a v1.1.0 release tweak.

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

- Versioned presets for common workflows such as upload, social sharing,
  thumbnails, and archival preservation.
- Strategy protocols for resize, target bytes, color conversion, metadata
  handling, and encoding so each feature can evolve without making the resolver
  monolithic.
- More fixture-driven characterization tests for edge formats such as CMYK JPEG,
  uncommon ICC profiles, wide-gamut sources, and server-oriented upload limits.
- Better diagnostics for why a result was returned: original passthrough, quality
  search, dimension reduction, metadata rewrite, format conversion, or fallback.
