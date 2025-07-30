# WICompress

![Platform](https://img.shields.io/badge/platform-iOS%2014.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange) ![SPM Support](https://img.shields.io/badge/SPM-Supported-brightgreen) ![License](https://img.shields.io/github/license/Weixi779/WICompress)

English | [简体中文](README_CN.md)

`WICompress` is a lightweight iOS image compression library that supports **JPEG, PNG, and HEIC** formats, using the **Luban algorithm** for intelligent compression and efficient image processing.

## Features

* **Luban Algorithm Compression** - Calculates optimal compression ratios to reduce file size while maintaining quality

* **Multi-format Support** - Supports JPEG, PNG, and HEIC formats with automatic format-specific compression methods

* **High Performance** - Optimized processing using `UIImage` and `CGImageDestination`

* **iOS 14+ Compatible** - Built with Swift Package Manager for modern iOS development

## Installation

### **Swift Package Manager (SPM)**

1. Open your project in Xcode, select **File** → **Add Packages**
2. Enter the repository URL: https://github.com/Weixi779/WICompress
3. Select the latest version and click **Add Package**

## Usage

### Image Resizing

Resize images using the Luban algorithm, which only compresses resolution:

```swift
import WICompress

let resizedImage = WICompress.resizeImage(originalImage)
```

### Image Quality Compression

Compress images with quality control and format preservation:

```swift
import WICompress

let compressedData = WICompress.compressImage(
    originalImage, 
    quality: 0.7, 
    formatData: imageData
)
```

### Parameters

- `image`: The `UIImage` to be compressed
- `quality`: Compression quality (0.0 - 1.0), default is 0.6
- `formatData`: Original image data used for format detection. If nil, defaults to JPEG compression

**Important Notes:**
- If `formatData` is nil, the library defaults to JPEG compression
- For HEIC images, providing `formatData` is strongly recommended for optimal compression results

## Processing Workflow

1. **Quality Compression**: Input (`UIImage` + `Data`) → Quality-compressed `Data`
2. **Resolution Adjustment**: Quality-compressed `Data` → `UIImage` → Resized `UIImage` (based on business requirements)
3. **Format Conversion**: Convert `UIImage` to required `Data` format for backend processing

## Example Project

The repository includes a comprehensive SwiftUI example project demonstrating WICompress functionality:

### Features Demonstrated
- **PhotosPicker Integration**: Select images from photo library with HEIC format preservation
- **PHPickerViewController**: UIKit-based picker for advanced use cases
- **Real-time Comparison**: Side-by-side comparison of original vs compressed images
- **Format Detection**: Automatic detection of JPEG, PNG, and HEIC formats
- **Live Photo Support**: Special handling for HEIC Live Photos
- **Compression Metrics**: File size reduction and compression ratio display

### Running the Example
1. Open `Example/WICompressExample/WICompressExample.xcodeproj`
2. Build and run on iOS device or simulator
3. Select images from your photo library to test compression

The example includes two main tabs:
- **PhotosPicker**: SwiftUI-based image selection
- **PHPicker**: UIKit-based image selection with enhanced debugging

## Compression Results

| PNG Result | HEIC Result 1 | HEIC Result 2 |
| --- | --- | --- |
| <img src="https://github.com/user-attachments/assets/901baf3d-93c5-4637-b15b-667a0f87bb1d" width="200"> | <img src="https://github.com/user-attachments/assets/582add53-6550-446b-ab0b-f0785ffc3327" width="200"> | <img src="https://github.com/user-attachments/assets/a960de4e-94e8-473e-828f-bf2db03dd1c2" width="200"> |

## License

WICompress is available under the MIT license. See the LICENSE file for more info.

---

#### **If you find this project helpful, please give it a Star ⭐️!**