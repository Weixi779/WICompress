# WICompress

![Platform](https://img.shields.io/badge/platform-iOS-blue)

![SPM Support](https://img.shields.io/badge/SPM-Supported-brightgreen)

![License](https://img.shields.io/github/license/Weixi779/WICompress)

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

### 调整图像质量

```swift
let compressedData = WICompress.compressImage(originalImage, quality: 0.7, formatData: imageData)
```

**注意：**

* **如果 formatData 为空，则默认使用 JPEG 进行压缩**

* **建议对 HEIC 图片提供 formatData，否则压缩效果可能较差**

## 操作流程

1. 调整图像质量 输入源 (应该为 UIImage 与 Data) => 质量压缩后Data
2. 质量压缩后Data 转为 UIImage 根据业务需要判断是否需要调整图片质量 => 调整尺寸后的UIImage
3. 根据所需上传数据类型种类 将 UIImage 转为对应 Data 进行业务处理

## 压缩效果

PNG效果

![Image](https://github.com/user-attachments/assets/901baf3d-93c5-4637-b15b-667a0f87bb1d)

HEIC效果1

![Image](https://github.com/user-attachments/assets/582add53-6550-446b-ab0b-f0785ffc3327)

HEVC效果2

![Image](https://github.com/user-attachments/assets/a960de4e-94e8-473e-828f-bf2db03dd1c2)

#### 📢 **如果你觉得这个项目有帮助，欢迎 Star ⭐️ 支持！**