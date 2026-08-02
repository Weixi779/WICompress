# WIImageIO Operations

Use inspection, decoding, transcoding, and encoding as small synchronous operations.

## Inspect before choosing work

``ImageDescriptor`` contains stable source facts and does not expose a
`CGImageSource`. Use ``ImageReader/colorSpace()`` only when a concrete source color
space is needed; resolving it may decode source pixels.

Runtime capabilities depend on the ImageIO implementation available on the current
platform:

```swift
let canRead = ImageReader.canDecode(.heic)
let canWrite = ImageReader.canEncode(.heic)
```

## Decode stored or display-oriented pixels

Use ``ImageReader/image(options:)`` for the complete stored frame. Its
``ImageFrame/orientation`` remains explicit and its ``ImageFrame/pixelSize`` describes
the stored pixel rows.

Use ``ImageReader/thumbnail(options:)`` for ImageIO-backed downsampling. By default it
applies display orientation and returns an `.up` frame. Set
`appliesOrientationTransform` to `false` only when the caller will handle orientation.

Both operations support static sources only. A multi-frame source throws
``ImageIOError/animatedSourceUnsupported(frameCount:)`` instead of silently selecting
frame zero.

## Transcode an encoded source

Use ``ImageReader/transcode(as:options:)`` when the requested representation, quality,
size, and metadata operation can be performed directly from the encoded source:

```swift
let output = try reader.transcode(
    as: .jpeg,
    options: ImageTranscodeOptions(
        compressionQuality: 0.8,
        metadata: .preserve
    )
)
```

Transcode preserves metadata by default. It throws
``ImageIOError/metadataTranscodeUnsupported(_:)`` when the requested metadata change
cannot be represented safely by this path. Decode and encode instead when pixels must
be transformed.

## Encode decoded or caller-owned pixels

Frames decoded by a reader retain an internal metadata snapshot. Callers can also wrap
their own pixels:

```swift
let frame = ImageFrame(image: cgImage, orientation: .up)
let output = try frame.encode(as: .png)
```

Encode strips metadata by default. Passing `.preserve` keeps modeled source metadata
only when the frame came from a reader; a caller-owned frame has no provenance.

## Own the scheduling boundary

WIImageIO is intentionally synchronous and does not provide a queue, Task wrapper,
global registry, or cancellation policy. Create and consume a reader within the
execution context selected by your application instead of sharing its ImageIO handle
across concurrency domains.

The higher-level `WICompress` product supplies cancellable async terminals. Internal
pipeline ownership is documented separately in the
[architecture documentation](https://github.com/Weixi779/WICompress/blob/main/docs/architecture/README.md).
