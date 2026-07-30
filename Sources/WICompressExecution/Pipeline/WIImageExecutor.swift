//
//  WIImageExecutor.swift
//  WICompressExecution
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import CoreGraphics
import WIImageDomain
import WIImageIO
import WIImageRaster

enum WIImageExecutor {
    static func execute(
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
                    options: CopyOptions(
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
            return try Transcoder.encode(
                image,
                as: plan.destinationTypeIdentifier,
                options: EncodeOptions(
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
        let sourceRect: Rect
        let orientation: Orientation
        if usesFullOrientedSource(
            geometry,
            descriptor: imageSource.descriptor
        ) {
            if let maximumPixelSize = thumbnailMaximumPixelSize(
                for: geometry,
                descriptor: imageSource.descriptor
            ) {
                do {
                    sourceImage = try imageSource.imageIOSource.thumbnail(
                        options: ThumbnailOptions(
                            maximumPixelSize: maximumPixelSize
                        )
                    )
                } catch {
                    throw map(error, destinationFormat: destinationFormat)
                }
                sourceRect = Rect(
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
                orientation = imageSource.descriptor.orientation
            }
        } else {
            do {
                sourceImage = try imageSource.imageIOSource.image()
            } catch {
                throw map(error, destinationFormat: destinationFormat)
            }
            sourceRect = geometry.sourceRect
            orientation = imageSource.descriptor.orientation
        }

        return try rasterImage(
            sourceImage,
            plan: WIImageRaster.Plan(
                canvasSize: geometry.canvasSize,
                sourceRect: sourceRect,
                destinationRect: geometry.destinationRect,
                orientation: orientation,
                alphaMode: rasterAlphaMode(
                    destinationFormat: destinationFormat
                ),
                canvasBackground: geometry.canvasBackground,
                imageBackground: rasterJPEGBackground(from: jpegBackground),
                colorSpace: rasterColorSpace(from: outputColorSpace)
            )
        )
    }

    private static func thumbnailMaximumPixelSize(
        for geometry: WIResolvedRender,
        descriptor: WIImageIO.Descriptor
    ) -> Int? {
        let displaySize = descriptor.orientedPixelSize
        let widthScale = geometry.destinationRect.width
            / Double(displaySize.width)
        let heightScale = geometry.destinationRect.height
            / Double(displaySize.height)
        let requiredScale = max(widthScale, heightScale)
        guard requiredScale < 1 else {
            return nil
        }

        let sourceMaximumPixelSize = max(
            displaySize.width,
            displaySize.height
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
        descriptor: WIImageIO.Descriptor
    ) -> Bool {
        let displaySize = descriptor.orientedPixelSize
        return geometry.sourceRect == Rect(
            x: 0,
            y: 0,
            width: Double(displaySize.width),
            height: Double(displaySize.height)
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

    private static func rasterAlphaMode(
        destinationFormat: WIImageFormat
    ) -> WIImageRaster.AlphaMode {
        destinationFormat == .jpeg ? .opaque : .preserve
    }

    private static func rasterJPEGBackground(
        from background: WIJPEGBackground?
    ) -> WIColor? {
        switch background {
        case .white:
            return WIColor(red: 1, green: 1, blue: 1)
        case .black:
            return WIColor(red: 0, green: 0, blue: 0)
        case .color(let color):
            return color
        case .disallow, nil:
            return nil
        }
    }

    private static func rasterColorSpace(
        from colorSpace: WIResolvedOutputColorSpace
    ) -> WIImageRaster.OutputColorSpace {
        guard let target = colorSpace.target else {
            return .source
        }

        return .convert(target)
    }

    private static func map(
        _ error: WIImageIO.Error,
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
        _ error: WIImageRaster.Error
    ) -> WICompressError {
        switch error {
        case .invalidSourceRect,
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
