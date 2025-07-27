#if os(iOS)

import UIKit
import UniformTypeIdentifiers

public final class WIImageProcessor {
    private var image: UIImage
    private var originalData: Data?
    
    init(image: UIImage) {
        self.image = image
    }
    
    init(image: UIImage, originalData: Data?) {
        self.image = image
        self.originalData = originalData
    }
    
    /// Compresses the image based on its format.
    /// - Parameters:
    ///   - format: The image format (`WIImageFormat`).
    ///   - quality: Compression quality (`0.0 - 1.0`).
    /// - Returns: Compressed `Data?`, or `nil` if compression fails.
    public func compress(format: WIImageFormat, quality: CGFloat) -> Data? {
        // Check if orientation correction is needed and apply it
        if needsOrientationCorrection() {
            image = correctOrientation()
        }
        
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
    
    /// Detects if the image needs orientation correction
    /// - Returns: `true` if the image needs orientation correction, `false` otherwise
    private func needsOrientationCorrection() -> Bool {
        guard let data = originalData else { return false }
        
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        
        // Check if it's HEIC format first
        guard let uti = CGImageSourceGetType(imageSource) else { return false }
        let utiString = uti as String
        
        if #available(iOS 16.0, *) {
            // iOS 16+ can use full Live Photo detection
            guard let type = UTType(utiString),
                  (type.conforms(to: .heif) || type.conforms(to: .heic)) else {
                return false
            }
            
            guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
                return false
            }
            
            // Check for Apple Live Photo indicators
            if let makerDict = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] {
                if makerDict["17"] != nil || makerDict["18"] != nil {
                    return true
                }
            }
            
            // Check HEIF dictionary for Live Photo indicators
            if let heifDict = properties[kCGImagePropertyHEIFDictionary as String] as? [String: Any] {
                return heifDict["IsLivePhoto"] as? Bool == true
            }
        } else {
            // iOS 14-15: Use simplified detection based on format and orientation
            guard utiString.contains("heic") || utiString.contains("heif") else {
                return false
            }
            
            guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
                return false
            }
            
            // For older iOS, just check if HEIC has orientation issues
            if let orientationValue = properties[kCGImagePropertyOrientation as String] as? Int,
               orientationValue != 1 {
                return true
            }
        }
        
        return false
    }
    
    /// Corrects image orientation for Live Photos that are rotated
    /// - Returns: A corrected `UIImage` if orientation needs fixing, otherwise returns the original image
    private func correctOrientation() -> UIImage {
        guard let data = originalData,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let orientationValue = properties[kCGImagePropertyOrientation as String] as? Int,
              let orientation = CGImagePropertyOrientation(rawValue: UInt32(orientationValue)) else {
            return image
        }
        
        // Only correct if orientation is not up (1)
        guard orientation != .up else { return image }
        
        guard let cgImage = image.cgImage else { return image }
        
        let transform = transformForOrientation(orientation)
        let size = transformedSize(originalSize: image.size, orientation: orientation)
        
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)
        
        return renderer.image { context in
            context.cgContext.concatenate(transform)
            
            let drawRect: CGRect
            switch orientation {
            case .left, .leftMirrored, .right, .rightMirrored:
                drawRect = CGRect(x: -image.size.height, y: 0, width: image.size.height, height: image.size.width)
            default:
                drawRect = CGRect(x: -image.size.width, y: -image.size.height, width: image.size.width, height: image.size.height)
            }
            
            context.cgContext.draw(cgImage, in: drawRect)
        }
    }
    
    /// Calculates the transform needed for the given orientation
    private func transformForOrientation(_ orientation: CGImagePropertyOrientation) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        
        switch orientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: image.size.width, y: image.size.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: image.size.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: image.size.height)
            transform = transform.rotated(by: -.pi / 2)
        default:
            break
        }
        
        switch orientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: image.size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: image.size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }
        
        return transform
    }
    
    /// Calculates the transformed size for the given orientation
    private func transformedSize(originalSize: CGSize, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: originalSize.height, height: originalSize.width)
        default:
            return originalSize
        }
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
