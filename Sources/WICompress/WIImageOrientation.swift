#if os(iOS)

import UIKit
import UniformTypeIdentifiers

public final class WIImageOrientation {
    
    /// Corrects image orientation for HEIC images that may be rotated
    /// - Parameters:
    ///   - image: The image that may need orientation correction
    ///   - data: The original image data for metadata analysis
    /// - Returns: A corrected `UIImage` if orientation needs fixing, otherwise returns the original image
    public static func correctOrientation(for image: UIImage, using data: Data?) -> UIImage {
        guard let data = data,
              needsOrientationCorrection(data: data) else {
            return image
        }
        
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let orientationValue = properties[kCGImagePropertyOrientation as String] as? Int,
              let orientation = CGImagePropertyOrientation(rawValue: UInt32(orientationValue)) else {
            return image
        }
        
        // Only correct if orientation is not up (1)
        guard orientation != .up else { return image }
        
        guard let cgImage = image.cgImage else { return image }
        
        let transform = transformForOrientation(orientation, imageSize: image.size)
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
    
    /// Detects if the image needs orientation correction
    /// - Parameter data: The original image data for metadata analysis
    /// - Returns: `true` if the image needs orientation correction, `false` otherwise
    private static func needsOrientationCorrection(data: Data) -> Bool {
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
    
    /// Calculates the transform needed for the given orientation
    private static func transformForOrientation(_ orientation: CGImagePropertyOrientation, imageSize: CGSize) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        
        switch orientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: imageSize.width, y: imageSize.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: imageSize.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: imageSize.height)
            transform = transform.rotated(by: -.pi / 2)
        default:
            break
        }
        
        switch orientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: imageSize.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: imageSize.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }
        
        return transform
    }
    
    /// Calculates the transformed size for the given orientation
    private static func transformedSize(originalSize: CGSize, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: originalSize.height, height: originalSize.width)
        default:
            return originalSize
        }
    }
}

#endif