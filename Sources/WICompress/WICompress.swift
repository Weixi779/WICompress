import Foundation
import CoreImage
import UniformTypeIdentifiers

public struct WICompress {
    
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
        
        let resizeRatio = WIImageUtils.calculateLubanRatio(width: width, height: height)
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
