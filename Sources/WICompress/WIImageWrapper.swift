#if os(iOS)

import UIKit
import UniformTypeIdentifiers

protocol WIImageResizing {
    
    /// Resize the image to a specific target size.
    /// - Parameter targetSize: The target size (`CGSize`) including width and height.
    /// - Returns: A new resized `UIImage?`, or `nil` if resizing fails.
    func resize(to targetSize: CGSize) -> UIImage?
    
    /// Resize the image by a given scale ratio.
    /// - Parameter ratio: The scale ratio (`Int`) by which to resize the image.
    /// - Returns: A new resized `UIImage?`, or `nil` if resizing fails.
    func resize(by ratio: Int) -> UIImage?
}

protocol WIImageHEICConversion {
    
    /// Convert the image to HEIC format data.
    /// - Parameter compressionQuality: Compression quality (0.0 - 1.0)
    /// - Returns: The HEIC formatted image data (`Data?`), or `nil` if conversion fails.
    func heicData(compressionQuality: CGFloat) -> Data?
}

protocol WIImageOrientable {
    
    /// Corrects the orientation of the image.
    func correctOrientation()
}

final class WIImageWrapper {
    private var image: UIImage
    
    init(image: UIImage) {
        self.image = image
    }
}

extension WIImageWrapper: WIImageResizing {
    
    func resize(to targetSize: CGSize) -> UIImage? {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    func resize(by ratio: Int) -> UIImage? {
        let targetWidth = CGFloat(max(Int(image.size.width) / ratio, 1))
        let targetHeight = CGFloat(max(Int(image.size.height) / ratio, 1))
        
        return resize(to: CGSize(width: targetWidth, height: targetHeight))
    }
}

extension WIImageWrapper: WIImageHEICConversion {
    
    func heicData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        
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

extension WIImageWrapper: WIImageOrientable {
    
    func correctOrientation() {
        guard image.imageOrientation != .up else { return }
        
        let renderer = UIGraphicsImageRenderer(size: image.size)
        image = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

#endif
