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
    /// - Returns: The resized `UIImage` if the operation succeeds, or the original image if resizing fails.
    static func resizeImage(_ image: UIImage) -> UIImage {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        
        let compressRatio = lubanFactor(width: width, height: height)
        let wrapper = WIImageWrapper(image: image)
        
        return wrapper.resize(by: compressRatio) ?? image
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
        let wrapper = WIImageWrapper(image: image)
        let format = WIImageFormat.init(data: formatData ?? Data())
        return wrapper.compress(format: format, quality: quality)
    }
}
#endif
