#if os(iOS)

import UIKit
import UniformTypeIdentifiers

public final class WIImageOrientation {
    
    /// Checks if the data needs orientation correction
    /// - Parameter data: The original image data for metadata analysis
    /// - Returns: `true` if orientation correction is needed, `false` otherwise
    public static func needsCorrection(using data: Data?) -> Bool {
        guard let data = data else { return false }
        return isLivePhoto(data: data)
    }
    
    /// Corrects image orientation for HEIC images that may be rotated
    /// - Parameters:
    ///   - image: The image that may need orientation correction
    ///   - data: The original image data for metadata analysis
    /// - Returns: A corrected `UIImage` if orientation needs fixing, otherwise returns the original image
    public static func correctOrientation(for image: UIImage, using data: Data?) -> UIImage {
        guard let data = data, isLivePhoto(data: data) else {
            return image
        }
        
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let orientationValue = properties[kCGImagePropertyOrientation as String] as? Int,
              let orientation = CGImagePropertyOrientation(rawValue: UInt32(orientationValue)) else {
            return image
        }
        
        // Only correct if orientation is not up (1)
        guard orientation != .up, let cgImage = image.cgImage else { return image }
        
        // Let UIImage handle the orientation correction automatically
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }
    
    /// Detects if the HEIC image is a Live Photo
    /// - Parameter data: The original HEIC image data for metadata analysis
    /// - Returns: `true` if the image is a Live Photo, `false` otherwise
    private static func isLivePhoto(data: Data) -> Bool {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return false
        }
        
        if #available(iOS 16.0, *) {
            // iOS 16+ can use full Live Photo detection
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
            // iOS 14-15: Check if HEIC has orientation issues
            if let orientationValue = properties[kCGImagePropertyOrientation as String] as? Int,
               orientationValue != 1 {
                return true
            }
        }
        
        return false
    }

}

#endif
