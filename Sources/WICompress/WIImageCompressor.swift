#if os(iOS)

import UIKit
import UniformTypeIdentifiers

public final class WIImageCompressor {
    private var image: UIImage
    
    init(image: UIImage) {
        self.image = image
    }
    
    /// Compresses the image based on its format.
    /// - Parameters:
    ///   - format: The image format (`WIImageFormat`).
    ///   - quality: Compression quality (`0.0 - 1.0`).
    /// - Returns: Compressed `Data?`, or `nil` if compression fails.
    public func compress(format: WIImageFormat, quality: CGFloat) -> Data? {
        switch format {
        case .jpeg:
            return image.jpegData(compressionQuality: quality)
        case .heif:
            return heicData(quality: quality)
        case .png:
            return image.pngData()
        case .unknown:
            return image.jpegData(compressionQuality: quality)
        }
    }
    
    /// Resizes the image to a specific target size.
    /// - Parameter targetSize: The desired size (`CGSize`), including width and height.
    /// - Returns: A new resized `UIImage`, or `nil` if resizing fails.
    public func resize(to targetSize: CGSize) -> UIImage? {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    /// Resizes the image by a given scale ratio.
    /// - Parameter ratio: The scale ratio (`Int`) by which to resize the image.
    /// - Returns: A new resized `UIImage`, or `nil` if resizing fails.
    public func resize(by ratio: Int) -> UIImage? {
        let targetWidth = CGFloat(max(Int(image.size.width) / ratio, 1))
        let targetHeight = CGFloat(max(Int(image.size.height) / ratio, 1))
        
        return resize(to: CGSize(width: targetWidth, height: targetHeight))
    }
    
    /// Converts the image to HEIC format.
    /// - Parameter quality: Compression quality (`0.0 - 1.0`).
    /// - Returns: HEIC formatted `Data?`, or `nil` if conversion fails.
    func heicData(quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else { return nil }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.heic.identifier as CFString, 1, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }

        return mutableData as Data
    }
}


#endif
