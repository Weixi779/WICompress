# WICompress

![Platform](https://img.shields.io/badge/platform-iOS%2014.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange) ![SPM Support](https://img.shields.io/badge/SPM-Supported-brightgreen) ![License](https://img.shields.io/github/license/Weixi779/WICompress)

[English](README.md) | 简体中文

`WICompress` 是一个轻量级的 iOS 图片压缩库，支持 **JPEG、PNG、HEIC** 格式，并使用 **Luban 算法** 进行智能压缩，提供高效的图像处理能力。

## 特性

* **Luban 算法压缩** - 计算最佳压缩比例，减少图片大小，同时保证质量

* **多格式支持** - 支持 JPEG、PNG、HEIC 格式，根据图片格式自动选择合适的压缩方法

* **高效快速** - 使用 `UIImage` 和 `CGImageDestination` 进行优化处理

* **iOS 14+ 兼容** - 使用 Swift Package Manager 构建，支持现代 iOS 开发

## 安装

### **使用 Swift Package Manager (SPM)**

1. 在 Xcode 中打开你的项目，选择 **File** → **Add Packages**
2. 输入仓库地址：https://github.com/Weixi779/WICompress
3. 选择最新版本，点击 **Add Package**

## 使用方法

### 调整图片尺寸

使用 Luban 算法调整图片尺寸，该方法只压缩分辨率：

```swift
import WICompress

let resizedImage = WICompress.resizeImage(originalImage)
```

### 图像质量压缩

支持质量控制和格式保持的图像压缩：

```swift
import WICompress

let compressedData = WICompress.compressImage(
    originalImage, 
    quality: 0.7, 
    formatData: imageData
)
```

### 参数说明

- `image`: 需要压缩的 `UIImage`
- `quality`: 压缩质量 (0.0 - 1.0)，默认为 0.6
- `formatData`: 用于格式检测的原始图片数据。如果为 nil，则默认使用 JPEG 压缩

**重要提示：**
- 如果 `formatData` 为空，则默认使用 JPEG 进行压缩
- 对于 HEIC 图片，强烈建议提供 `formatData` 以获得最佳压缩效果

## 处理流程

1. **质量压缩**: 输入源 (`UIImage` + `Data`) → 质量压缩后的 `Data`
2. **分辨率调整**: 质量压缩后的 `Data` → `UIImage` → 调整尺寸后的 `UIImage` (根据业务需要)
3. **格式转换**: 将 `UIImage` 转为所需的 `Data` 格式进行后端处理

## 示例项目

仓库包含了完整的 SwiftUI 示例项目，演示 WICompress 的功能：

### 演示功能
- **PhotosPicker 集成**: 从相册选择图片并保持 HEIC 格式
- **PHPickerViewController**: 基于 UIKit 的选择器，适用于高级使用场景
- **实时对比**: 原图与压缩图的并排比较
- **格式检测**: 自动检测 JPEG、PNG、HEIC 格式
- **Live Photo 支持**: 对 HEIC Live Photos 的特殊处理
- **压缩指标**: 文件大小减少和压缩比显示

### 运行示例
1. 打开 `Example/WICompressExample/WICompressExample.xcodeproj`
2. 在 iOS 设备或模拟器上构建运行
3. 从相册选择图片测试压缩功能

示例包含两个主要标签页：
- **PhotosPicker**: 基于 SwiftUI 的图片选择
- **PHPicker**: 基于 UIKit 的图片选择，提供增强调试功能

## 压缩效果

| PNG效果 | HEIC效果1 | HEIC效果2 |
| --- | --- | --- |
| <img src="https://github.com/user-attachments/assets/901baf3d-93c5-4637-b15b-667a0f87bb1d" width="200"> | <img src="https://github.com/user-attachments/assets/582add53-6550-446b-ab0b-f0785ffc3327" width="200"> | <img src="https://github.com/user-attachments/assets/a960de4e-94e8-473e-828f-bf2db03dd1c2" width="200"> |

## 系统要求

- iOS 14.0+
- Swift 5.0+
- Xcode 12.0+

## 许可证

WICompress 基于 MIT 许可证开源。详情请查看 LICENSE 文件。

---

#### **如果你觉得这个项目有帮助，欢迎 Star ⭐️ 支持！**