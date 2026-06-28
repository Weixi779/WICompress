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

        let image = try renderBitmap(thumbnail, plan: plan)

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

    private static func renderBitmap(
        _ image: CGImage,
        plan: WIWritePlan
    ) throws(WICompressError) -> CGImage {
        let colorSpace = try outputColorSpace(for: image, plan: plan)
        let alphaMode = try renderAlphaMode(for: plan)
        let bitmapInfo = bitmapInfo(for: image, alphaMode: alphaMode)
        let size = plan.targetPixelSize ?? WIPixelSize(width: image.width, height: image.height)

        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw WICompressError.colorConversionFailed
        }

        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.interpolationQuality = .high
        context.setRenderingIntent(.relativeColorimetric)

        if case .opaqueJPEG(let background?) = alphaMode {
            context.setFillColor(try background.cgColor(in: colorSpace))
            context.fill(rect)
        }

        context.draw(image, in: rect)

        guard let renderedImage = context.makeImage() else {
            throw WICompressError.colorConversionFailed
        }

        return renderedImage
    }

    private static func outputColorSpace(
        for image: CGImage,
        plan: WIWritePlan
    ) throws(WICompressError) -> CGColorSpace {
        if let target = plan.outputColorSpace.target {
            return try target.makeCGColorSpace()
        }

        return rgbColorSpace(from: image) ?? CGColorSpaceCreateDeviceRGB()
    }

    private static func renderAlphaMode(for plan: WIWritePlan) throws(WICompressError) -> WIRenderAlphaMode {
        guard plan.destinationFormat == .jpeg else {
            return .preserveSourceAlpha
        }

        return .opaqueJPEG(background: try resolvedJPEGBackground(from: plan.jpegBackground))
    }

    private static func resolvedJPEGBackground(
        from background: WIJPEGBackground?
    ) throws(WICompressError) -> WIResolvedJPEGBackground? {
        switch background {
        case .white:
            return WIResolvedJPEGBackground(color: WIColor(red: 1, green: 1, blue: 1))
        case .black:
            return WIResolvedJPEGBackground(color: WIColor(red: 0, green: 0, blue: 0))
        case .color(let color):
            return WIResolvedJPEGBackground(color: color)
        case .disallow, nil:
            return nil
        }
    }

    private static func bitmapInfo(for image: CGImage, alphaMode: WIRenderAlphaMode) -> UInt32 {
        switch alphaMode {
        case .preserveSourceAlpha:
            return resizedBitmapInfo(for: image)
        case .opaqueJPEG:
            return CGImageAlphaInfo.noneSkipLast.rawValue
        }
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

private struct WIResolvedJPEGBackground: Sendable, Equatable {
    var color: WIColor

    func cgColor(in destinationColorSpace: CGColorSpace) throws(WICompressError) -> CGColor {
        let sourceColorSpace = try color.colorSpace.makeCGColorSpace()
        guard sourceColorSpace.model == .rgb else {
            throw WICompressError.unsupportedColorSpace
        }

        let components = [
            clamped(color.red),
            clamped(color.green),
            clamped(color.blue),
            clamped(color.alpha)
        ]
        guard let sourceColor = CGColor(colorSpace: sourceColorSpace, components: components),
              let destinationColor = sourceColor.converted(
                to: destinationColorSpace,
                intent: .relativeColorimetric,
                options: nil
              ) else {
            throw WICompressError.colorConversionFailed
        }

        return destinationColor
    }

    private func clamped(_ value: Double) -> CGFloat {
        guard value.isFinite else {
            return 0
        }

        return CGFloat(min(max(value, 0), 1))
    }
}

private enum WIRenderAlphaMode: Sendable, Equatable {
    case preserveSourceAlpha
    case opaqueJPEG(background: WIResolvedJPEGBackground?)
}
