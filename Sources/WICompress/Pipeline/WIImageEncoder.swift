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
            let image = try render(imageSource, plan: plan)
            return try encodeRendered(image, imageSource: imageSource, plan: plan)
        case .redrawCanvas:
            let image = try render(imageSource, plan: plan)
            return try encodeRendered(image, imageSource: imageSource, plan: plan)
        }
    }

    static func render(_ imageSource: WIImageSource, plan: WIWritePlan) throws(WICompressError) -> CGImage {
        switch plan.path {
        case .redrawBitmap:
            return try renderRedrawnBitmap(imageSource, plan: plan)
        case .redrawCanvas:
            return try renderCanvasBitmap(imageSource, plan: plan)
        case .returnOriginal, .copyFromSource:
            throw WICompressError.writePlanUnavailable
        }
    }

    static func encodeRendered(
        _ image: CGImage,
        imageSource: WIImageSource,
        plan: WIWritePlan
    ) throws(WICompressError) -> Data {
        try encodeRenderedImage(image, imageSource: imageSource, plan: plan)
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

    private static func renderRedrawnBitmap(_ imageSource: WIImageSource, plan: WIWritePlan) throws(WICompressError) -> CGImage {
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

        return try renderBitmap(thumbnail, plan: plan)
    }

    private static func renderCanvasBitmap(_ imageSource: WIImageSource, plan: WIWritePlan) throws(WICompressError) -> CGImage {
        guard let renderGeometry = plan.renderGeometry else {
            throw WICompressError.writePlanUnavailable
        }

        guard let decodedImage = CGImageSourceCreateImageAtIndex(
            imageSource.cgImageSource,
            0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        ) else {
            throw WICompressError.imageDecodeFailed
        }

        let normalizedImage = imageSource.info.orientation == 1
            ? decodedImage
            : try renderOrientationNormalizedBitmap(decodedImage, info: imageSource.info)
        return try renderBitmap(normalizedImage, plan: plan, renderGeometry: renderGeometry)
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

    private static func encodeRenderedImage(
        _ image: CGImage,
        imageSource: WIImageSource,
        plan: WIWritePlan
    ) throws(WICompressError) -> Data {
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            plan.destinationTypeIdentifier as CFString,
            1,
            nil
        ) else {
            throw WICompressError.destinationCreationFailed(plan.destinationFormat)
        }

        let properties = renderedDestinationProperties(for: plan, imageSource: imageSource)
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw WICompressError.encodeFailed(plan.destinationFormat)
        }

        return outputData as Data
    }

    private static func renderedDestinationProperties(
        for plan: WIWritePlan,
        imageSource: WIImageSource
    ) -> [CFString: Any] {
        var properties = destinationProperties(for: plan, imageSource: imageSource)
        // Reset the tag so readers do not rotate pixels that were already transformed.
        properties[kCGImagePropertyOrientation] = 1
        return properties
    }

    private static func renderBitmap(
        _ image: CGImage,
        plan: WIWritePlan
    ) throws(WICompressError) -> CGImage {
        let size = plan.targetPixelSize ?? WIPixelSize(width: image.width, height: image.height)
        let renderGeometry = WIRenderGeometry(
            canvasSize: size,
            destinationRect: WIRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)),
            background: nil
        )

        return try renderBitmap(image, plan: plan, renderGeometry: renderGeometry)
    }

    private static func renderBitmap(
        _ image: CGImage,
        plan: WIWritePlan,
        renderGeometry: WIRenderGeometry
    ) throws(WICompressError) -> CGImage {
        let colorSpace = try outputColorSpace(for: image, plan: plan)
        let alphaMode = try renderAlphaMode(for: plan)
        let bitmapInfo = bitmapInfo(for: image, alphaMode: alphaMode)
        let size = renderGeometry.canvasSize

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

        if let background = renderGeometry.background {
            context.setFillColor(try WIResolvedJPEGBackground(color: background).cgColor(in: colorSpace))
            context.fill(rect)
        }

        if case .opaqueJPEG(let background?) = alphaMode {
            context.setFillColor(try background.cgColor(in: colorSpace))
            let fillRect = renderGeometry.background == nil ? rect : renderGeometry.destinationRect.cgRect
            context.fill(fillRect)
        }

        context.draw(image, in: renderGeometry.destinationRect.cgRect)

        guard let renderedImage = context.makeImage() else {
            throw WICompressError.colorConversionFailed
        }

        return renderedImage
    }

    private static func renderOrientationNormalizedBitmap(
        _ image: CGImage,
        info: WIImageInfo
    ) throws(WICompressError) -> CGImage {
        let colorSpace = rgbColorSpace(from: image) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = resizedBitmapInfo(for: image)

        guard let context = CGContext(
            data: nil,
            width: info.displayWidth,
            height: info.displayHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw WICompressError.colorConversionFailed
        }

        context.interpolationQuality = .high
        context.setRenderingIntent(.relativeColorimetric)
        applyOrientationTransform(
            to: context,
            orientation: info.orientation,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )

        guard let renderedImage = context.makeImage() else {
            throw WICompressError.colorConversionFailed
        }

        return renderedImage
    }

    private static func applyOrientationTransform(
        to context: CGContext,
        orientation: Int,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        let width = CGFloat(pixelWidth)
        let height = CGFloat(pixelHeight)

        switch orientation {
        case 2:
            context.translateBy(x: width, y: 0)
            context.scaleBy(x: -1, y: 1)
        case 3:
            context.translateBy(x: width, y: height)
            context.rotate(by: .pi)
        case 4:
            context.translateBy(x: 0, y: height)
            context.scaleBy(x: 1, y: -1)
        case 5:
            context.translateBy(x: height, y: 0)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: 0, y: width)
            context.rotate(by: -.pi / 2)
        case 6:
            context.translateBy(x: 0, y: width)
            context.rotate(by: -.pi / 2)
        case 7:
            context.translateBy(x: height, y: 0)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: height, y: 0)
            context.rotate(by: .pi / 2)
        case 8:
            context.translateBy(x: height, y: 0)
            context.rotate(by: .pi / 2)
        default:
            break
        }
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

private extension WIRect {
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
