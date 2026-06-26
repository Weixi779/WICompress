//
//  WIImageEncoder.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import CoreGraphics
import ImageIO

enum WIImageEncoder {
    static func encode(_ imageSource: WIImageSource, plan: WIWritePlan) throws(WICompressError) -> Data {
        switch plan.path {
        case .returnOriginal:
            return imageSource.data
        case .copyFromSource:
            return try encodeFromSource(imageSource, plan: plan)
        case .redrawBitmap:
            return try encodeRedrawnBitmap(imageSource, plan: plan)
        }
    }

    private static func encodeFromSource(_ imageSource: WIImageSource, plan: WIWritePlan) throws(WICompressError) -> Data {
        // This path lets ImageIO keep metadata and orientation tags coupled to the source.
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            plan.destinationTypeIdentifier as CFString,
            1,
            nil
        ) else {
            throw WICompressError.destinationCreationFailed(plan.destinationFormat)
        }

        var properties = destinationProperties(for: plan)
        if let maxPixelSize = plan.maxPixelSize {
            properties[kCGImageDestinationImageMaxPixelSize] = maxPixelSize
        }

        CGImageDestinationAddImageFromSource(
            destination,
            imageSource.cgImageSource,
            0,
            properties as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            throw WICompressError.encodeFailed(plan.destinationFormat)
        }

        return outputData as Data
    }

    private static func encodeRedrawnBitmap(_ imageSource: WIImageSource, plan: WIWritePlan) throws(WICompressError) -> Data {
        // Thumbnail creation bakes orientation into pixels, which matches the default strip path.
        var thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        if let maxPixelSize = plan.maxPixelSize {
            thumbnailOptions[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            imageSource.cgImageSource,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw WICompressError.thumbnailCreationFailed
        }

        var image = thumbnail
        if let targetPixelSize = plan.targetPixelSize {
            image = try resizedImage(image, targetPixelSize: targetPixelSize)
        }
        image = try destinationImage(from: image, plan: plan)

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            plan.destinationTypeIdentifier as CFString,
            1,
            nil
        ) else {
            throw WICompressError.destinationCreationFailed(plan.destinationFormat)
        }

        var properties = destinationProperties(for: plan, imageSource: imageSource)
        // Reset the tag so readers do not rotate pixels that were already transformed.
        properties[kCGImagePropertyOrientation] = 1

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw WICompressError.encodeFailed(plan.destinationFormat)
        }

        return outputData as Data
    }

    private static func destinationProperties(
        for plan: WIWritePlan,
        imageSource: WIImageSource? = nil
    ) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]

        if plan.metadataPolicy == .preserve, let imageSource {
            properties.merge(preservedMetadataProperties(from: imageSource)) { _, new in new }
        }

        if let quality = plan.quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        return properties
    }

    private static func destinationImage(
        from image: CGImage,
        plan: WIWritePlan
    ) throws(WICompressError) -> CGImage {
        guard plan.destinationFormat == .jpeg else {
            return image
        }

        switch plan.jpegBackground {
        case .white:
            return try flattenedJPEGImage(image, background: .white)
        case .black:
            return try flattenedJPEGImage(image, background: .black)
        case .disallow, nil:
            return image
        }
    }

    private static func flattenedJPEGImage(
        _ image: CGImage,
        background: WIJPEGBackground
    ) throws(WICompressError) -> CGImage {
        let colorSpace = rgbColorSpace(from: image) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw WICompressError.thumbnailCreationFailed
        }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.interpolationQuality = .high

        switch background {
        case .white:
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        case .black:
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        case .disallow:
            break
        }

        context.fill(rect)
        context.draw(image, in: rect)

        guard let flattenedImage = context.makeImage() else {
            throw WICompressError.thumbnailCreationFailed
        }

        return flattenedImage
    }

    private static func resizedImage(
        _ image: CGImage,
        targetPixelSize: WIPixelSize
    ) throws(WICompressError) -> CGImage {
        guard image.width != targetPixelSize.width || image.height != targetPixelSize.height else {
            return image
        }

        let colorSpace = rgbColorSpace(from: image) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = resizedBitmapInfo(for: image)
        guard let context = CGContext(
            data: nil,
            width: targetPixelSize.width,
            height: targetPixelSize.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw WICompressError.thumbnailCreationFailed
        }

        let rect = CGRect(
            x: 0,
            y: 0,
            width: targetPixelSize.width,
            height: targetPixelSize.height
        )
        context.interpolationQuality = .high
        context.draw(image, in: rect)

        guard let resizedImage = context.makeImage() else {
            throw WICompressError.thumbnailCreationFailed
        }

        return resizedImage
    }

    private static func resizedBitmapInfo(for image: CGImage) -> UInt32 {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return CGImageAlphaInfo.premultipliedLast.rawValue
        case .none, .noneSkipFirst, .noneSkipLast:
            return CGImageAlphaInfo.noneSkipLast.rawValue
        @unknown default:
            return CGImageAlphaInfo.premultipliedLast.rawValue
        }
    }

    private static func rgbColorSpace(from image: CGImage) -> CGColorSpace? {
        guard let colorSpace = image.colorSpace, colorSpace.model == .rgb else {
            return nil
        }

        return colorSpace
    }

    private static func preservedMetadataProperties(from imageSource: WIImageSource) -> [CFString: Any] {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            imageSource.cgImageSource,
            0,
            nil
        ) as? [CFString: Any] else {
            return [:]
        }

        let metadataKeys: [CFString] = [
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyExifDictionary,
            kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyIPTCDictionary,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyMakerAppleDictionary,
            kCGImagePropertyMakerCanonDictionary,
            kCGImagePropertyMakerNikonDictionary,
            kCGImagePropertyMakerMinoltaDictionary,
            kCGImagePropertyMakerFujiDictionary,
            kCGImagePropertyMakerOlympusDictionary,
            kCGImagePropertyMakerPentaxDictionary
        ]

        return metadataKeys.reduce(into: [:]) { result, key in
            if let value = properties[key] {
                result[key] = value
            }
        }
    }
}
