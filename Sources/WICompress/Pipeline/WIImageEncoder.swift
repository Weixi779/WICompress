//
//  WIImageEncoder.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
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

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource.cgImageSource,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw WICompressError.thumbnailCreationFailed
        }

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
        // Reset the tag so readers do not rotate pixels that were already transformed.
        properties[kCGImagePropertyOrientation] = 1

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw WICompressError.encodeFailed(plan.destinationFormat)
        }

        return outputData as Data
    }

    private static func destinationProperties(for plan: WIWritePlan) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]

        if let quality = plan.quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        return properties
    }
}
