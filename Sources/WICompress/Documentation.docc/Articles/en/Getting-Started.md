# Getting Started with WICompress

Add WICompress to an app and run a complete image operation with the default Process.

## Add the package

Add `https://github.com/Weixi779/WICompress.git` as a Swift package dependency and
link the `WICompress` product to your target.

```swift
import WICompress
```

WICompress 2.0 requires the Swift 6.2 toolchain. Projects that cannot adopt that
toolchain should continue using WICompress 1.x.

## Process encoded data

The shortest call applies ``WIImageProcess/default``. The default uses Luban V2
sizing, a lossy quality of `0.6`, strips non-display metadata, and preserves the
source representation and normal display color semantics when possible.

```swift
let result = try await WICompressor.process(originalData)

let encodedData = result.data
let format = result.format
let pixelSize = result.pixelSize
let byteCount = result.byteCount
```

`WIResult` is the common result of both Process and Target operations. Decode
`result.data` into a platform image only at the UI boundary.

## Process a file

Use a file URL to let ImageIO open the encoded source directly:

```swift
let result = try await WICompressor.process(contentsOf: fileURL)
```

The Data and file forms have the same image semantics. The file form passes its URL
directly to ImageIO instead of first creating a complete `Data` copy. ImageIO may
still read any or all of the file while operating; original passthrough additionally
materializes `Data` when the encoded bytes must be returned.

## Choose the right terminal

- Use `WICompressor.process(_:using:)` for explicit resizing, cropping, quality,
  and output requirements.
- Use `WICompressor.compress(_:to:)` for a hard encoded byte limit.

See <doc:Process-and-Target> for the two request models and
<doc:Concurrency-and-Cancellation> for execution behavior.
