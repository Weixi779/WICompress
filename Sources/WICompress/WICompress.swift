import Foundation
import CoreImage
import UniformTypeIdentifiers

enum WIImageFormat {
    case jpeg
    case png
    case heif
    case unknown
}

struct WICompress {
    
    /// 确定图片的格式类型
    /// - Parameter data: 图片数据
    /// - Returns: 图片格式枚举
    private static func determineImageType(_ data: Data) -> WIImageFormat {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(imageSource) else {
            return .unknown
        }
        
        // 转换 UTI 为 UTType
        guard let type = UTType(uti as String) else { return .unknown }
        
        // 判断图片格式
        if type.conforms(to: .jpeg) {
            return .jpeg
        } else if type.conforms(to: .png) {
            return .png
        } else if type.conforms(to: .heif) || type.conforms(to: .heic) {
            return .heif
        } else {
            return .unknown
        }
    }
    
    /// 确保尺寸为偶数
    /// - Parameter size: 原始尺寸
    /// - Returns: 偶数尺寸
    private static func ensureEven(_ size: Int) -> Int {
        return size % 2 == 1 ? size + 1 : size
    }
    
    /// Luban算法用于计算压缩比例
    /// - Parameters:
    ///   - width: 图片宽度
    ///   - height: 图片高度
    /// - Returns: 压缩比例
    private static func lubanFactor(width: Int, height: Int) -> Int {
        let originalWidth = ensureEven(width)
        let originalHeight = ensureEven(height)
        
        let longSide = max(originalWidth, originalHeight)
        let shortSide = min(originalWidth, originalHeight)
        let aspectRatio = Double(shortSide) / Double(longSide)
        
        switch aspectRatio {
        case 0.5625...1:
            switch longSide {
            case ..<1664:
                return 1
            case 1664..<4990:
                return 2
            case 4990..<10240:
                return 4
            default:
                return max(longSide / 1280, 1)
            }
        case 0.5..<0.5625:
            return longSide > 1280 ? max(longSide / 1280, 1) : 1
        default:
            return Int(ceil(Double(longSide) / 1280.0))
        }
    }
}

#if os(iOS)
import UIKit

extension WICompress {
    
    /// 压缩图片并返回 UIImage
    /// - Parameter image: 原始图片
    /// - Returns: 压缩后的图片
    static func resizeImageInLuban(_ image: UIImage) -> UIImage? {
        return compressSizeInLuban(image)
    }
    
    /// 压缩图片并转换为数据
    /// - Parameters:
    ///   - image: 原始图片
    ///   - quality: 压缩质量
    ///   - formatData: 原始图片数据用于确定格式
    /// - Returns: 压缩后的图片数据
    static func compressImageToData(_ image: UIImage, quality: CGFloat = 0.6, formatData: Data? = nil) -> Data? {
        let format = determineImageType(formatData ?? Data())
        return compressData(image, quality: quality, format: format)
    }
}

extension WICompress {
    
    /// 使用 Luban 算法压缩图片尺寸
    /// - Parameter image: 原始图片
    /// - Returns: 压缩后的图片
    private static func compressSizeInLuban(_ image: UIImage) -> UIImage? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        
        let compressRatio = lubanFactor(width: width, height: height)
        return image.resize(by: compressRatio)
    }
    
    /// 将 UIImage 转换为数据
    /// - Parameters:
    ///   - image: 要转换的图片
    ///   - quality: 压缩质量（仅适用于 JPEG/HEIC）
    /// - Returns: 图片数据
    private static func compressData(_ image: UIImage, quality: CGFloat = 1.0, format: WIImageFormat) -> Data? {
        switch format {
        case .jpeg:
            return image.jpegData(compressionQuality: quality)
        case .heif:
            return image.heicData(compressionQuality: quality)
        case .png:
            return image.pngData()
        default:
            return image.jpegData(compressionQuality: quality)
        }
    }
}

// MARK: - UIImage Resize
extension UIImage {
    
    func resize(to targetSize: CGSize) -> UIImage? {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    func resize(by ratio: Int) -> UIImage? {
        let targetWidth = CGFloat(max(Int(self.size.width) / ratio, 1))
        let targetHeight = CGFloat(max(Int(self.size.height) / ratio, 1))
        
        return self.resize(to: CGSize(width: targetWidth, height: targetHeight))
    }
}

// MARK: - UIImage to HEIC
extension UIImage {
    
    func fixOrientation() -> UIImage {
        guard self.imageOrientation != .up else { return self }
        
        let renderer = UIGraphicsImageRenderer(size: self.size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
    }
    
    func heicData(compressionQuality: CGFloat) -> Data? {
        let normalized = self.fixOrientation()
        
        guard let ciImage = CIImage(image: normalized) else { return nil }
        
        let targetWidth = normalized.size.width
        let targetHeight = normalized.size.height
        let scaleX = targetWidth / normalized.size.width
        let scaleY = targetHeight / normalized.size.height
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let scaledCIImage = ciImage.transformed(by: transform)
        
        let context = CIContext(options: nil)
        guard let scaledCGImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else { return nil }
        
        let resizedImage = UIImage(cgImage: scaledCGImage, scale: 1.0, orientation: .up)
        
        return resizedImage.compressHeicData(compressionQuality: compressionQuality)
    }
    
    private func compressHeicData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage = self.cgImage else { return nil }
        
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.heic.identifier as CFString, 1, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else { return nil }
        
        return mutableData as Data
    }
}
#endif
