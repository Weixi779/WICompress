import Foundation
import ImageIO

enum WIImageEncoder {
    static func encode(_ imageSource: WIImageSource, plan: WIWritePlan) throws -> Data {
        switch plan.path {
        case .returnOriginal:
            return imageSource.data
        case .copyFromSource:
            return try encodeFromSource(imageSource, plan: plan)
        case .redrawBitmap:
            return try encodeRedrawnBitmap(imageSource, plan: plan)
        }
    }

    private static func encodeFromSource(_ imageSource: WIImageSource, plan: WIWritePlan) throws -> Data {
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

    private static func encodeRedrawnBitmap(_ imageSource: WIImageSource, plan: WIWritePlan) throws -> Data {
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
