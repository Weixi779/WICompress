# WICompress

`WICompress` 是一个轻量级的 iOS 图片压缩库，支持 **JPEG、PNG、HEIC** 格式，并使用 **Luban 算法** 进行智能压缩，提供高效的图像处理能力。

## 特性

* **Luban 算法压缩** - 计算最佳压缩比例，减少图片大小，同时保证质量

* **支持 JPEG / PNG / HEIC** - 根据图片格式自动选择合适的压缩方法

* **高效快速** - 使用 `UIImage` 和 `CGImageDestination` 进行优化处理

## 安装

### **使用 Swift Package Manager (SPM)**

1. 在 Xcode 中打开你的项目，选择 **File** → **Add Packages**
2. 输入仓库地址：https://github.com/Weixi779/WICompress
3. 选择最新版本，点击 **Add Package**

## 使用方法

### 调整图片尺寸

会根据对应luban系数压缩, 该方法只压缩分辨率

```swift
let resizedImage = WICompress.resizeImage(originalImage)
```

### 压缩图片整体大小

```swift
let compressedData = WICompress.compressImage(originalImage, quality: 0.7, formatData: imageData)
```

**注意：**

* **如果 formatData 为空，则默认使用 JPEG 进行压缩**

* **建议对 HEIC 图片提供 formatData，否则压缩效果可能较差**

#### 📢 **如果你觉得这个项目有帮助，欢迎 Star ⭐️ 支持！**