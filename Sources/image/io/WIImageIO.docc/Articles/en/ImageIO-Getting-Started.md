# Getting Started with WIImageIO

Open an encoded image once, inspect its facts, and select the cheapest operation that satisfies your request.

## Add the product

Add `https://github.com/Weixi779/WICompress.git` as a Swift package dependency and
link the `WIImageIO` product to your target.

```swift
import UniformTypeIdentifiers
import WIImageIO
```

## Open Data or a file

``ImageReader`` accepts encoded Data and file URLs:

```swift
let dataReader = try ImageReader(imageData)
let fileReader = try ImageReader(contentsOf: fileURL)
```

A file reader passes its URL directly to ImageIO instead of first materializing the
file as `Data`. ImageIO may still read any or all file contents while inspecting or
processing the source. The reader performs inspection during initialization and
caches one ``ImageDescriptor``.

If only source facts are needed, use the inspection conveniences:

```swift
let descriptor = try ImageReader.inspect(imageData)
let fileDescriptor = try ImageReader.inspect(contentsOf: fileURL)
```

The descriptor reports encoded type and format, byte count, stored and display-oriented
pixel sizes, orientation, frame count, alpha information, modeled metadata categories,
and gain-map presence. `hasAlpha` is optional because some containers cannot provide a
reliable answer during property inspection.

## Decode a thumbnail

Use thumbnail decoding when the full-resolution pixels are not required:

```swift
let frame = try dataReader.thumbnail(
    options: ImageThumbnailOptions(maximumPixelSize: 1_280)
)
```

Thumbnail decoding applies display orientation by default, so the returned frame has
`.up` orientation. ``ImageReader/image(options:)`` instead decodes the stored source
frame and retains its explicit orientation.

## Encode the frame

```swift
let output = try frame.encode(
    as: .jpeg,
    options: ImageEncodeOptions(
        compressionQuality: 0.72,
        metadata: .strip
    )
)
```

An ImageFrame created by a reader carries a snapshot of available metadata provenance.
A frame created from caller-owned `CGImage` pixels has no source metadata to preserve.

Continue with <doc:ImageIO-Operations> to choose between decode, transcode, and encode.
