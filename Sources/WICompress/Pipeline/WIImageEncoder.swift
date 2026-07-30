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
    static func encode(
        _ imageSource: WIImageSource,
        plan: WIExecutionPlan
    ) throws(WICompressError) -> Data {
        switch plan.operation {
        case .returnOriginal:
            return try imageSource.originalData()
        case .copyFromSource:
            do {
                return try imageSource.imageIOSource.copy(
                    as: plan.destinationTypeIdentifier,
                    options: WIImageCopyOptions(
                        compressionQuality: plan.quality
                    )
                )
            } catch {
                throw map(error, destinationFormat: plan.destinationFormat)
            }
        case .render:
            let image = try render(imageSource, plan: plan)
            return try encodeRendered(
                image,
                imageSource: imageSource,
                plan: plan
            )
        }
    }

    static func render(
        _ imageSource: WIImageSource,
        plan: WIExecutionPlan
    ) throws(WICompressError) -> CGImage {
        guard case .render(let geometry) = plan.operation else {
            throw .executionPlanUnavailable
        }

        return try render(
            imageSource,
            geometry: geometry,
            destinationFormat: plan.destinationFormat,
            jpegBackground: plan.jpegBackground,
            outputColorSpace: plan.outputColorSpace
        )
    }

    static func encodeRendered(
        _ image: CGImage,
        imageSource: WIImageSource,
        plan: WIExecutionPlan
    ) throws(WICompressError) -> Data {
        do {
            return try WIImageTranscoder.encode(
                image,
                as: plan.destinationTypeIdentifier,
                options: WIImageEncodeOptions(
                    compressionQuality: plan.quality
                ),
                preservingMetadataFrom: plan.metadata == .preserve
                    ? imageSource.imageIOSource
                    : nil
            )
        } catch {
            throw map(error, destinationFormat: plan.destinationFormat)
        }
    }

    private static func render(
        _ imageSource: WIImageSource,
        geometry: WIResolvedRender,
        destinationFormat: WIImageFormat,
        jpegBackground: WIJPEGBackground?,
        outputColorSpace: WIResolvedOutputColorSpace
    ) throws(WICompressError) -> CGImage {
        let sourceImage: CGImage
        let sourceRect: WIRect
        let orientation: WIImageRaster.Orientation
        if usesFullOrientedSource(geometry, info: imageSource.info) {
            if let maximumPixelSize = thumbnailMaximumPixelSize(
                for: geometry,
                info: imageSource.info
            ) {
                do {
                    sourceImage = try imageSource.imageIOSource.thumbnail(
                        options: WIThumbnailOptions(
                            maximumPixelSize: maximumPixelSize
                        )
                    )
                } catch {
                    throw map(error, destinationFormat: destinationFormat)
                }
                sourceRect = WIRect(
                    x: 0,
                    y: 0,
                    width: Double(sourceImage.width),
                    height: Double(sourceImage.height)
                )
                orientation = .up
            } else {
                do {
                    sourceImage = try imageSource.imageIOSource.image()
                } catch {
                    throw map(error, destinationFormat: destinationFormat)
                }
                sourceRect = geometry.sourceRect
                guard let sourceOrientation = WIImageRaster.Orientation(
                    rawValue: imageSource.info.orientation
                ) else {
                    throw .imageInfoUnavailable
                }
                orientation = sourceOrientation
            }
        } else {
            do {
                sourceImage = try imageSource.imageIOSource.image()
            } catch {
                throw map(error, destinationFormat: destinationFormat)
            }
            sourceRect = geometry.sourceRect
            guard let sourceOrientation = WIImageRaster.Orientation(
                rawValue: imageSource.info.orientation
            ) else {
                throw .imageInfoUnavailable
            }
            orientation = sourceOrientation
        }

        return try rasterImage(
            sourceImage,
            plan: WIImageRaster.Plan(
                canvasSize: rasterPixelSize(geometry.canvasSize),
                sourceRect: WIImageRaster.Rect(
                    x: sourceRect.x,
                    y: sourceRect.y,
                    width: sourceRect.width,
                    height: sourceRect.height
                ),
                destinationRect: WIImageRaster.Rect(
                    x: geometry.destinationRect.x,
                    y: geometry.destinationRect.y,
                    width: geometry.destinationRect.width,
                    height: geometry.destinationRect.height
                ),
                orientation: orientation,
                alphaMode: rasterAlphaMode(
                    destinationFormat: destinationFormat
                ),
                canvasBackground: geometry.canvasBackground.map(rasterColor),
                imageBackground: rasterJPEGBackground(from: jpegBackground),
                colorSpace: rasterColorSpace(from: outputColorSpace)
            )
        )
    }

    private static func thumbnailMaximumPixelSize(
        for geometry: WIResolvedRender,
        info: WIImageInfo
    ) -> Int? {
        let widthScale = geometry.destinationRect.width
            / Double(info.displayWidth)
        let heightScale = geometry.destinationRect.height
            / Double(info.displayHeight)
        let requiredScale = max(widthScale, heightScale)
        guard requiredScale < 1 else {
            return nil
        }

        let sourceMaximumPixelSize = max(
            info.displayWidth,
            info.displayHeight
        )
        guard let requiredMaximumPixelSize = Int(
            exactly: (Double(sourceMaximumPixelSize) * requiredScale)
                .rounded(.up)
        ) else {
            return nil
        }
        return min(
            max(requiredMaximumPixelSize, 1),
            sourceMaximumPixelSize
        )
    }

    private static func usesFullOrientedSource(
        _ geometry: WIResolvedRender,
        info: WIImageInfo
    ) -> Bool {
        geometry.sourceRect == WIRect(
            x: 0,
            y: 0,
            width: Double(info.displayWidth),
            height: Double(info.displayHeight)
        )
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
        destinationFormat: WIImageFormat
    ) -> WIImageRaster.AlphaMode {
        destinationFormat == .jpeg ? .opaque : .preserve
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
            return .executionPlanUnavailable
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
