import Foundation
import CoreImage
import UniformTypeIdentifiers

struct WICompress {
    
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
    
    /// Resize Image By luban Algorithm
    /// - Parameter image: The image to be compressed
    /// - Returns: Resize uiimage, or nil if conversion fails
    static func resizeImage(_ image: UIImage) -> UIImage? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        
        let compressRatio = lubanFactor(width: width, height: height)
        return image.resize(by: compressRatio)
    }
    
    /// Compress the image to the specified format data
    /// It is strongly recommended to provide the data when the image source is HEIC; otherwise, the compression results will be poor.
    /// - Parameters:
    ///   - image: The image to be compressed
    ///   - quality: Compression quality (0.0 - 1.0), default is 0.6
    ///   - formatData: Data used to determine the image format, defaults to .jpeg if nil
    /// - Returns: Compressed image data, or nil if conversion fails
    static func compressImage(
        _ image: UIImage,
        quality: CGFloat = 0.6,
        formatData: Data? = nil
    ) -> Data? {
        let format = WIImageFormat.init(data: formatData ?? Data())
        return format.compress(image: image, quality: quality)
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
