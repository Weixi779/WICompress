import Foundation
import CoreImage
import UniformTypeIdentifiers

enum WIImageFormat {
    case jpeg
    case png
    case heif
    case unknown
    
    init(data: Data) {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let uti = CGImageSourceGetType(imageSource),
            let type = UTType(uti as String)
        else {
            self = .unknown
            return
        }
        
        // 判断图片格式
        if type.conforms(to: .jpeg) {
            self = .jpeg
        } else if type.conforms(to: .png) {
            self = .png
        } else if type.conforms(to: .heif) || type.conforms(to: .heic) {
            self = .heif
        } else {
            self = .unknown
        }
    }
}

#if os(iOS)

import UIKit

extension WIImageFormat {
    
    func compress(image: UIImage, quality: CGFloat) -> Data? {
        switch self {
        case .jpeg:
            return image.jpegData(compressionQuality: quality)
        case .heif:
            return image.heicData(compressionQuality: quality)
        case .png:
            return image.pngData()
        case .unknown:
            return image.jpegData(compressionQuality: quality)
        }
    }
}

#endif
