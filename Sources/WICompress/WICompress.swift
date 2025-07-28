import Foundation
import CoreImage
import UniformTypeIdentifiers

public struct WICompress {
    
    private static func ensureEven(_ size: Int) -> Int {
        return size % 2 == 1 ? size + 1 : size
    }
    
    /// Calculates the compression ratio using the Luban algorithm.
    /// - Parameters:
    ///   - width: The width of the image.
    ///   - height: The height of the image.
    /// - Returns: The computed compression ratio.
    public static func calculateLubanRatio(width: Int, height: Int) -> Int {
        let longSide = max(ensureEven(width), ensureEven(height))
        let shortSide = min(ensureEven(width), ensureEven(height))
        let aspectRatio = Double(shortSide) / Double(longSide)

        switch aspectRatio {
        case 0.5625...1 where longSide < 1664:
            return 1
        case 0.5625...1 where longSide < 4990:
            return 2
        case 0.5625...1 where longSide < 10240:
            return 4
        case 0.5625...1:
            return max(longSide / 1280, 1)
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
    public static func resizeImage(_ image: UIImage) -> UIImage {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        
        let resizeRatio = calculateLubanRatio(width: width, height: height)
        let compressor = WIImageCompressor(image: image)
        
        return compressor.resize(by: resizeRatio) ?? image
    }
    
    /// Compress the image to the specified format data
    /// It is strongly recommended to provide the data when the image source is HEIC; otherwise, the compression results will be poor.
    /// - Parameters:
    ///   - image: The image to be compressed
    ///   - quality: Compression quality (0.0 - 1.0), default is 0.6
    ///   - formatData: Data used to determine the image format, defaults to .jpeg if nil
    /// - Returns: Compressed image data, or nil if conversion fails
    public static func compressImage(
        _ image: UIImage,
        quality: CGFloat = 0.6,
        formatData: Data? = nil
    ) -> Data? {
        let format = WIImageFormat(data: formatData ?? Data())
        
        let resizedImage = resizeImage(image)
        
        let finalImage = format.isHEIF ? 
            WIImageOrientation.correctOrientation(for: resizedImage, using: formatData) : 
            resizedImage
        
        let compressor = WIImageCompressor(image: finalImage)
        return compressor.compress(format: format, quality: quality)
    }
}
#endif
