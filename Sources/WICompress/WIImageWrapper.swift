//
//  WIImageWrapper.swift
//  WICompress
//
//  Created by 孙世伟 on 2025/2/27.
//

#if os(iOS)

import UIKit
import UniformTypeIdentifiers

protocol WIImageResizing {
    func resize(to targetSize: CGSize) -> UIImage?
    func resize(by ratio: Int) -> UIImage?    
}

protocol WIImageHEICConversion {
    func heicData(compressionQuality: CGFloat) -> Data?
}

protocol WIImageOrientable {
    func correctOrientation()
}

final class WIImageWrapper {
    private var image: UIImage
    
    init(image: UIImage) {
        self.image = image
    }
}

// MARK: - WIImageResizing

extension WIImageWrapper: WIImageResizing {
    func resize(to targetSize: CGSize) -> UIImage? {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    /// 按比例调整图片大小
    func resize(by ratio: Int) -> UIImage? {
        let targetWidth = CGFloat(max(Int(image.size.width) / ratio, 1))
        let targetHeight = CGFloat(max(Int(image.size.height) / ratio, 1))
        
        return resize(to: CGSize(width: targetWidth, height: targetHeight))
    }
}

// MARK: - WIImageHEICConversion
extension WIImageWrapper: WIImageHEICConversion {
    
    /// 转换为 HEIC 格式数据
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

// MARK: - WIImageOrientable
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
