# WICompress Roadmap Notes

This document captures future design discussion. It is not part of any release
contract.

## WICompress 2.0 Domain Redesign

The shared 2.0 architecture boundary is frozen in
[`V2_DOMAIN_MODEL_CN.md`](V2_DOMAIN_MODEL_CN.md).

The two public product lines are tracked separately:

- [`V2_IMAGE_PROCESS_CN.md`](V2_IMAGE_PROCESS_CN.md) owns the frozen
  `WIImageProcess` behavior contract.
- [`V2_COMPRESSION_TARGET_CN.md`](V2_COMPRESSION_TARGET_CN.md) owns the frozen
  target-compression contract.

The 1.x-to-2.0 source migration is tracked in
[`V2_MIGRATION_CN.md`](V2_MIGRATION_CN.md).

The ImageIO boundary is tracked in
[`V2_IMAGE_IO_CN.md`](V2_IMAGE_IO_CN.md). It freezes the public `WIImageIO`
product, typed `ImageReader → ImageFrame → encode` chain, synchronous primitive model, and
static-image scope without exposing raw ImageIO implementation details.

The internal Core Graphics raster boundary is tracked in
[`V2_IMAGE_RASTER_CN.md`](V2_IMAGE_RASTER_CN.md). It freezes the package-only
target, resolved-geometry input, one-pass crop/resize rendering, hidden bitmap
surface, pixel-only coordinates, and synchronous primitive model.

The current 1.x inventory, combination matrix, external research, and historical
evidence remain in [`V2_CAPABILITY_MAP_CN.md`](V2_CAPABILITY_MAP_CN.md). It is
not an implementation contract.

The 2.0 product and infrastructure boundaries are conceptually complete.
Implementation status:

- Completed: Swift 6.2 package baseline and public `WIImageIO` product.
- Completed: typed ImageReader inspection, ImageFrame decode/thumbnail, source transcode,
  chained encode, runtime capabilities, and Pipeline error mapping.
- Completed: removal of the temporary `CGImageSource` migration bridge; the
  `WICompress` target no longer owns raw ImageIO source/destination operations.
- Completed: package-only `WIImageRaster` target with one resolved-plan entry;
  bitmap rendering, orientation normalization, crop/resize, two-layer
  backgrounds, alpha flattening, and color conversion no longer live in
  `WIImageExecutor`.
- Completed: `WIImageDomain` owns shared pixel-size, color, format, metadata,
  orientation, and geometry facts. `WICompressDomain` owns Process, Target,
  Output, crop, resizing, and Luban request semantics. ImageIO, Raster, and
  Execution consume the shared facts without mirrored Core values or
  product-boundary field conversions.
- Completed: request-scoped `ImagePipeline` owns source and ImageIO/Raster
  execution. Process and Target validation, decision ownership, Target feedback
  search, working-image reuse, and result checks now live directly in the
  pipeline without architecture-level Resolver, ExecutionPlan, Executor, or
  Solver types. `WICompressor` calls the package-only Pipeline terminals
  directly; the public `WICompress` target remains an umbrella facade.
- Completed: `ImageFormat` is a shared Image Domain fact and
  `WICompressError` belongs to Compress Domain. ImageIO owns format detection
  and exposes `ImageIOError`; the Pipeline maps it to the terminal error.
- Completed: synchronous `WIImageProcess` vertical slice with public
  `WIPixelSize`, resizing slot and built-ins, aspect-ratio crop, shared Output
  values, pure geometry calculation, and direct pipeline execution.
- Completed: file-backed Process URL execution, on-demand original-byte reads,
  two-axis-safe thumbnail sampling, and overflow validation before Raster.
- Completed: Target now uses the shared `WIImageOutput`; its frozen default is
  Alpha-aware PNG/JPEG, stripped metadata, and conversion to sRGB. The duplicate
  public `WICompressionOutput` has been removed.
- Completed: Target now exposes the frozen `WICompressionSizing` contract,
  resolves crop and base size once, and runs its feedback search directly in
  `ImagePipeline`. The old public geometry/preference/canvas domain and
  transitional `WIWritePlan` adapter have been removed.
- Completed: the 1.x Options/Policy terminals, legacy resolver, and write-plan
  adapter have been removed rather than maintained as a second architecture.
- Completed: the package and module remain `WICompress`, while the public
  uninhabited terminal namespace is now `WICompressor`; no compatibility alias
  keeps the 1.x facade alive.
- Next: add the Swift 6.2 asynchronous terminals over the same synchronous
  execution core.

Implementation details must not reopen the frozen product domains without
conflicting evidence.

## Target Compression Refinements

- Whether to expose diagnostics for why a target result was returned: original
  passthrough, quality search, dimension reduction, metadata rewrite, format
  conversion, or fallback.
- Whether PNG target compression should add an optional refinement pass between
  the last too-large size and the first fitting size.
- Whether future lossy PNG behavior, such as palette quantization, should be
  modeled as a separate explicit policy.

## Metadata Control

The 2.0 metadata model is complete. `ImageMetadataOptions` is an `OptionSet`
covering Exif, location, IPTC, TIFF, and maker-note categories:

```swift
let uploadMetadata = ImageMetadataOptions.preserve
    .subtracting(.gps)
```

`.strip` and `.preserve` remain readable aliases for the empty and complete
sets. Color profiles remain output color-space semantics, and orientation
remains display geometry: redraw paths bake it into pixels and write
orientation `1`. GPS-only removal can use ImageIO's lossless source-copy
path when no pixel or quality change is requested.

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
