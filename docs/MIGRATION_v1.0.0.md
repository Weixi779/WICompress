# WICompress v1.0.0 迁移说明

v1.0.0 是一次 breaking change。核心目标是把 WICompress 从
`UIImage` 工具库重构为 ImageIO-based `Data` 压缩核心。

## 1. 删除的 API

以下旧 API 已删除：

```swift
WICompress.resizeImage(_:)
WICompress.compressImage(_:quality:formatData:)
```

原因：

- `UIImage` / `NSImage` 不是图片容器，它们不稳定表达原始格式、metadata、
  orientation tag、HDR auxiliary data 等信息。
- 旧 API 需要额外传入 `formatData:` 来反推格式，调用心智不清晰。
- ImageIO 可以直接从原始 `Data` 读取格式、尺寸、方向和 metadata，因此
  public API 应该以 `Data` 为中心。

## 2. 新入口

```swift
let compressedData = try WICompress.compress(originalData)
```

文件 URL：

```swift
let compressedData = try WICompress.compress(contentsOf: imageURL)
```

显式配置：

```swift
let compressedData = try WICompress.compress(
    originalData,
    options: WICompressOptions(
        resize: .luban,
        format: .preserve,
        metadata: .strip,
        quality: .compression(0.7)
    )
)
```

## 3. 旧代码到新代码

### 旧：压缩 UIImage

```swift
let compressedData = WICompress.compressImage(
    image,
    quality: 0.7,
    formatData: originalData
)
```

### 新：压缩原始 Data

```swift
let compressedData = try WICompress.compress(
    originalData,
    options: WICompressOptions(quality: .compression(0.7))
)
```

如果 UI 需要展示结果，在业务层自行解码：

```swift
let previewImage = UIImage(data: compressedData)
```

## 4. 从相册选择图片时怎么改

核心原则：尽量保留 picker 给你的原始 `Data`，不要只保留 `UIImage`。

### PhotosPicker

```swift
guard let originalData = try await item.loadTransferable(type: Data.self) else {
    throw MyError.missingImageData
}

let compressedData = try WICompress.compress(originalData)
let image = UIImage(data: compressedData)
```

### PHPickerViewController

业务层应从 `NSItemProvider` 或文件 representation 中取原始图片 data，然后：

```swift
let compressedData = try WICompress.compress(originalData)
```

不要先把图片解码成 `UIImage`，再尝试从 `UIImage` 反推出原始格式。

## 5. 行为差异

### 5.1 失败从 `nil` 改为 `throws`

旧 API 用 `nil` 表示失败，新 API 抛 `WICompressError`。

```swift
do {
    let compressedData = try WICompress.compress(data)
} catch let error as WICompressError {
    print(error)
}
```

如果业务确实只想要旧式可空结果，可以在调用处写：

```swift
let compressedData = try? WICompress.compress(data)
```

### 5.2 默认保留源格式

v1.0.0 的 `format` 首版只有 `.preserve`：

- JPEG -> JPEG
- PNG -> PNG
- HEIC/HEIF -> HEIC/HEIF

旧 API 在 `formatData == nil` 时可能退回 JPEG；v1 不再提供这种隐式行为。

### 5.3 默认剥离 metadata

默认配置：

```swift
WICompressOptions(
    resize: .luban,
    format: .preserve,
    metadata: .strip,
    quality: .compression(0.6)
)
```

`.metadata(.strip)` 会剥离 Exif / GPS / TIFF / maker notes 等可剥离 metadata。
这符合上传压缩的默认预期。

如果业务需要保留 GPS / Exif / orientation tag：

```swift
let compressedData = try WICompress.compress(
    data,
    options: WICompressOptions(metadata: .preserve)
)
```

注意：v1.0.0 的 `.preserve` 不承诺保留 HDR gain map。Gain map 后续会作为
独立能力设计。

### 5.4 quality 对 PNG 是 no-op

PNG 是无损格式，`quality: .compression(...)` 不会被解释成有损压缩。

JPEG / HEIC 这类有损格式会收到 `kCGImageDestinationLossyCompressionQuality`。

`.quality(.none)` 只表示“不显式设置 lossy quality”，不等于无损。

### 5.5 可能返回原始 Data

当压缩结果不小于原图，并且原始 data 已经满足当前 options 的可观察要求时，
内部 size guard 可能直接返回原始 data。

这个兜底不会绕过 metadata / orientation / format 等 policy。例如默认
`.metadata(.strip)` 下，如果原图带 GPS，不会因为输出更大就返回带 GPS 的原图。

## 6. 暂不支持的能力

v1.0.0 不包含：

- `UIImage` / `NSImage` convenience adapter
- Live Photo 压缩
- async API
- 显式 PNG -> JPEG / HEIC -> JPEG 等格式转换
- PNG alpha 背景色合成
- target bytes / max file size
- HDR gain map preserve
- 动图输出

### Live Photo

Live Photo 至少包括：

- still photo resource
- paired video resource
- 两者的 pairing metadata

只压缩 still image data 不能得到一个完整的 Live Photo。后续如果支持，应在
Photos 资源层设计，而不是放进首版 ImageIO core。

### PNG -> JPEG

PNG -> JPEG 确实是常见上传需求，但 JPEG 不支持 alpha。透明像素必须合成到
某个背景色上，而背景色又涉及色彩空间。v1 不会偷偷铺白。

后续如果支持，预期会通过类似下面的显式配置表达：

```swift
format: .jpeg(background: .white)
```

## 7. 推荐迁移步骤

1. 找到所有 `resizeImage` / `compressImage` 调用。
2. 调整图片选择、文件读取或网络层，保留原始 `Data`。
3. 用 `WICompress.compress(data, options:)` 替换旧调用。
4. 把旧的 `nil` 判断改成 `do/catch` 或局部 `try?`。
5. 如果业务依赖 GPS/Exif，显式设置 `metadata: .preserve`。
6. 如果业务依赖 JPEG-only 上传，v1 暂不直接支持 PNG -> JPEG；应先在业务侧
   处理格式需求，或等待后续 format policy 扩展。
7. 跑 `swift test` 和 iOS simulator 测试。

## 8. 最小迁移示例

```swift
import WICompress

func uploadData(from originalData: Data) throws -> Data {
    try WICompress.compress(
        originalData,
        options: WICompressOptions(
            metadata: .strip,
            quality: .compression(0.7)
        )
    )
}
```

UI 预览：

```swift
let compressedData = try uploadData(from: originalData)
let image = UIImage(data: compressedData)
```
