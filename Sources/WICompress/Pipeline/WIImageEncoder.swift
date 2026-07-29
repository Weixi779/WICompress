//
//  WIImageEncoder.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import CoreGraphics
import WIImageIO
import WIImageRaster

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
        do {
            return try imageSource.imageIOSource.copy(
                as: plan.destinationTypeIdentifier,
                options: WIImageCopyOptions(
                    maximumPixelSize: plan.maxPixelSize,
                    compressionQuality: plan.quality
                )
            )
        } catch {
            throw map(error, destinationFormat: plan.destinationFormat)
        }
    }

    private static func renderRedrawnBitmap(_ imageSource: WIImageSource, plan: WIWritePlan) throws(WICompressError) -> CGImage {
        // Thumbnail creation bakes orientation into pixels, which matches the default strip path.
        let thumbnail: CGImage
        do {
            thumbnail = try imageSource.imageIOSource.thumbnail(
                options: WIThumbnailOptions(maximumPixelSize: plan.maxPixelSize)
            )
        } catch {
            throw map(error, destinationFormat: plan.destinationFormat)
        }

        let size = plan.targetPixelSize ?? WIPixelSize(
            width: thumbnail.width,
            height: thumbnail.height
        )
        return try rasterImage(
            thumbnail,
            plan: WIImageRaster.Plan(
                canvasSize: rasterPixelSize(size),
                sourceRect: WIImageRaster.Rect(
                    x: 0,
                    y: 0,
                    width: Double(thumbnail.width),
                    height: Double(thumbnail.height)
                ),
                destinationRect: WIImageRaster.Rect(
                    x: 0,
                    y: 0,
                    width: Double(size.width),
                    height: Double(size.height)
                ),
                alphaMode: rasterAlphaMode(for: plan),
                imageBackground: rasterJPEGBackground(from: plan.jpegBackground),
                colorSpace: rasterColorSpace(from: plan.outputColorSpace)
            )
        )
    }

    private static func renderCanvasBitmap(_ imageSource: WIImageSource, plan: WIWritePlan) throws(WICompressError) -> CGImage {
        guard let renderGeometry = plan.renderGeometry else {
            throw WICompressError.writePlanUnavailable
        }

        let decodedImage: CGImage
        do {
            decodedImage = try imageSource.imageIOSource.image()
        } catch {
            throw map(error, destinationFormat: plan.destinationFormat)
        }

        guard let orientation = WIImageRaster.Orientation(
            rawValue: imageSource.info.orientation
        ) else {
            throw WICompressError.imageInfoUnavailable
        }

        let canvasHeight = Double(renderGeometry.canvasSize.height)
        let destinationRect = renderGeometry.destinationRect
        return try rasterImage(
            decodedImage,
            plan: WIImageRaster.Plan(
                canvasSize: rasterPixelSize(renderGeometry.canvasSize),
                sourceRect: WIImageRaster.Rect(
                    x: 0,
                    y: 0,
                    width: Double(imageSource.info.displayWidth),
                    height: Double(imageSource.info.displayHeight)
                ),
                destinationRect: WIImageRaster.Rect(
                    x: destinationRect.x,
                    y: canvasHeight - destinationRect.y - destinationRect.height,
                    width: destinationRect.width,
                    height: destinationRect.height
                ),
                orientation: orientation,
                alphaMode: rasterAlphaMode(for: plan),
                canvasBackground: renderGeometry.background.map(rasterColor),
                imageBackground: rasterJPEGBackground(from: plan.jpegBackground),
                colorSpace: rasterColorSpace(from: plan.outputColorSpace)
            )
        )
    }

    private static func encodeRenderedImage(
        _ image: CGImage,
        imageSource: WIImageSource,
        plan: WIWritePlan
    ) throws(WICompressError) -> Data {
        do {
            return try WIImageTranscoder.encode(
                image,
                as: plan.destinationTypeIdentifier,
                options: WIImageEncodeOptions(compressionQuality: plan.quality),
                preservingMetadataFrom: plan.metadataPolicy == .preserve
                    ? imageSource.imageIOSource
                    : nil
            )
        } catch {
            throw map(error, destinationFormat: plan.destinationFormat)
        }
    }

    private static func rasterImage(
        _ image: CGImage,
        plan: WIImageRaster.Plan
    ) throws(WICompressError) -> CGImage {
        do {
            return try WIImageRaster.image(image, plan: plan)
        } catch {
            throw map(error)
        }
    }

    private static func rasterPixelSize(
        _ size: WIPixelSize
    ) -> WIImageRaster.PixelSize {
        WIImageRaster.PixelSize(width: size.width, height: size.height)
    }

    private static func rasterAlphaMode(
        for plan: WIWritePlan
    ) -> WIImageRaster.AlphaMode {
        plan.destinationFormat == .jpeg ? .opaque : .preserve
    }

    private static func rasterJPEGBackground(
        from background: WIJPEGBackground?
    ) -> WIImageRaster.Color? {
        switch background {
        case .white:
            return rasterColor(WIColor(red: 1, green: 1, blue: 1))
        case .black:
            return rasterColor(WIColor(red: 0, green: 0, blue: 0))
        case .color(let color):
            return rasterColor(color)
        case .disallow, nil:
            return nil
        }
    }

    private static func rasterColor(_ color: WIColor) -> WIImageRaster.Color {
        WIImageRaster.Color(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha,
            colorSpace: rasterColorSpace(from: color.colorSpace)
        )
    }

    private static func rasterColorSpace(
        from colorSpace: WIResolvedOutputColorSpace
    ) -> WIImageRaster.ColorSpace {
        guard let target = colorSpace.target else {
            return .source
        }

        return rasterColorSpace(from: target)
    }

    private static func rasterColorSpace(
        from colorSpace: WIColorSpace
    ) -> WIImageRaster.ColorSpace {
        switch colorSpace {
        case .sRGB:
            return .sRGB
        case .displayP3:
            return .displayP3
        case .iccProfile(let data):
            return .iccProfile(data)
        }
    }

    private static func map(
        _ error: WIImageIOError,
        destinationFormat: WIImageFormat
    ) -> WICompressError {
        switch error {
        case .invalidImageData:
            return .invalidImageData
        case .sourcePropertiesUnavailable,
             .invalidPixelSize,
             .pixelCountOverflow:
            return .imageInfoUnavailable
        case .fileReadFailed(let url),
             .fileSizeUnavailable(let url):
            return .fileReadFailed(url)
        case .imageCreationFailed:
            return .imageDecodeFailed
        case .thumbnailCreationFailed:
            return .thumbnailCreationFailed
        case .animatedSourceUnsupported(let frameCount):
            return .animatedSourceUnsupported(frameCount: frameCount)
        case .destinationCreationFailed:
            return .destinationCreationFailed(destinationFormat)
        case .destinationFinalizationFailed:
            return .encodeFailed(destinationFormat)
        }
    }

    private static func map(
        _ error: WIImageRasterError
    ) -> WICompressError {
        switch error {
        case .invalidPixelSize,
             .invalidSourceRect,
             .invalidDestinationRect,
             .sourceRectOutOfBounds:
            return .writePlanUnavailable
        case .unsupportedColorSpace:
            return .unsupportedColorSpace
        case .invalidICCProfile:
            return .invalidICCProfile
        case .nonOpaqueBackground:
            return .nonOpaqueJPEGBackground
        case .rowByteOverflow,
             .bitmapByteCountOverflow,
             .colorConversionFailed,
             .contextCreationFailed,
             .imageCreationFailed:
            return .colorConversionFailed
        }
    }
}
