//
//  ImagePipeline.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/31.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import WIImageDomain
import WIImageIO
import WIImageRaster

final class ImagePipeline {
    enum Input {
        case data(Data)
        case file(URL)
    }

    let input: Input
    let source: WIImageIO.Source
    let descriptor: WIImageIO.Descriptor

    var byteCount: Int {
        source.byteCount
    }

    convenience init(data: Data) throws(WICompressError) {
        let source: WIImageIO.Source
        do {
            source = try WIImageIO.Source(data: data)
        } catch {
            throw Self.mapSourceError(error)
        }

        try self.init(
            input: .data(data),
            source: source
        )
    }

    convenience init(contentsOf url: URL) throws(WICompressError) {
        let source: WIImageIO.Source
        do {
            source = try WIImageIO.Source(contentsOf: url)
        } catch {
            throw Self.mapSourceError(error)
        }

        try self.init(
            input: .file(url),
            source: source
        )
    }

    private init(
        input: Input,
        source: WIImageIO.Source
    ) throws(WICompressError) {
        let descriptor = source.descriptor
        guard descriptor.frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: descriptor.frameCount)
        }

        self.input = input
        self.source = source
        self.descriptor = descriptor
    }

    func originalData() throws(WICompressError) -> Data {
        switch input {
        case .data(let data):
            return data
        case .file(let url):
            do {
                return try Data(contentsOf: url)
            } catch {
                throw .fileReadFailed(url)
            }
        }
    }

    func sourceColorSpace() throws(WICompressError) -> WIColorSpace? {
        do {
            return try source.colorSpace()
        } catch {
            throw Self.mapSourceError(error)
        }
    }

    func originalResult() throws(WICompressError) -> WIResult {
        WIResult(
            data: try originalData(),
            format: descriptor.format,
            pixelSize: descriptor.orientedPixelSize
        )
    }

    func result(
        for data: Data
    ) throws(WICompressError) -> WIResult {
        let outputSource: WIImageIO.Source
        do {
            outputSource = try WIImageIO.Source(data: data)
        } catch {
            throw Self.mapSourceError(error)
        }

        let outputDescriptor = outputSource.descriptor
        guard outputDescriptor.frameCount == 1 else {
            throw .animatedSourceUnsupported(
                frameCount: outputDescriptor.frameCount
            )
        }
        guard outputDescriptor.format != .unknown else {
            throw .unsupportedSourceFormat(
                outputDescriptor.type?.identifier
            )
        }

        return WIResult(
            data: data,
            format: outputDescriptor.format,
            pixelSize: outputDescriptor.orientedPixelSize
        )
    }

    func execute(
        _ plan: WIExecutionPlan
    ) throws(WICompressError) -> Data {
        switch plan.operation {
        case .returnOriginal:
            return try originalData()
        case .copyFromSource:
            return try copyFromSource(
                as: plan.destinationType,
                destinationFormat: plan.destinationFormat,
                metadata: plan.metadata,
                quality: plan.quality
            )
        case .render:
            let image = try render(plan)
            return try encodeRendered(image, plan: plan)
        }
    }

    func copyFromSource(
        output: WIResolvedImageOutput,
        metadata: WIImageMetadataOptions,
        quality: Double?
    ) throws(WICompressError) -> Data {
        try copyFromSource(
            as: output.destinationType,
            destinationFormat: output.destinationFormat,
            metadata: metadata,
            quality: quality
        )
    }

    func renderAndEncode(
        geometry: WIResolvedRender,
        output: WIResolvedImageOutput,
        metadata: WIImageMetadataOptions,
        quality: Double?
    ) throws(WICompressError) -> Data {
        let image = try render(
            geometry: geometry,
            destinationFormat: output.destinationFormat,
            jpegBackground: output.jpegBackground,
            outputColorSpace: output.colorSpace
        )
        return try encodeRendered(
            image,
            as: output.destinationType,
            destinationFormat: output.destinationFormat,
            metadata: metadata,
            quality: quality
        )
    }

    func render(
        _ plan: WIExecutionPlan
    ) throws(WICompressError) -> CGImage {
        guard case .render(let geometry) = plan.operation else {
            throw .executionPlanUnavailable
        }

        return try render(
            geometry: geometry,
            destinationFormat: plan.destinationFormat,
            jpegBackground: plan.jpegBackground,
            outputColorSpace: plan.outputColorSpace
        )
    }

    func encodeRendered(
        _ image: CGImage,
        plan: WIExecutionPlan
    ) throws(WICompressError) -> Data {
        try encodeRendered(
            image,
            as: plan.destinationType,
            destinationFormat: plan.destinationFormat,
            metadata: plan.metadata,
            quality: plan.quality
        )
    }

    private func copyFromSource(
        as destinationType: UTType,
        destinationFormat: WIImageFormat,
        metadata: WIImageMetadataOptions,
        quality: Double?
    ) throws(WICompressError) -> Data {
        do {
            return try source.copy(
                as: destinationType,
                options: CopyOptions(
                    compressionQuality: quality,
                    metadata: metadata
                )
            )
        } catch {
            throw Self.mapExecutionError(
                error,
                destinationFormat: destinationFormat
            )
        }
    }

    private func encodeRendered(
        _ image: CGImage,
        as destinationType: UTType,
        destinationFormat: WIImageFormat,
        metadata: WIImageMetadataOptions,
        quality: Double?
    ) throws(WICompressError) -> Data {
        do {
            return try Encoder.encode(
                image,
                as: destinationType,
                options: EncodeOptions(
                    compressionQuality: quality,
                    metadata: metadata
                ),
                metadataFrom: source
            )
        } catch {
            throw Self.mapExecutionError(
                error,
                destinationFormat: destinationFormat
            )
        }
    }

    private func render(
        geometry: WIResolvedRender,
        destinationFormat: WIImageFormat,
        jpegBackground: WIJPEGBackground?,
        outputColorSpace: WIResolvedOutputColorSpace
    ) throws(WICompressError) -> CGImage {
        let sourceImage: CGImage
        let sourceRect: Rect
        let orientation: Orientation
        if usesFullOrientedSource(geometry) {
            if let maximumPixelSize = thumbnailMaximumPixelSize(
                for: geometry
            ) {
                do {
                    sourceImage = try source.thumbnail(
                        options: ThumbnailOptions(
                            maximumPixelSize: maximumPixelSize
                        )
                    )
                } catch {
                    throw Self.mapExecutionError(
                        error,
                        destinationFormat: destinationFormat
                    )
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
                    sourceImage = try source.image()
                } catch {
                    throw Self.mapExecutionError(
                        error,
                        destinationFormat: destinationFormat
                    )
                }
                sourceRect = geometry.sourceRect
                orientation = descriptor.orientation
            }
        } else {
            do {
                sourceImage = try source.image()
            } catch {
                throw Self.mapExecutionError(
                    error,
                    destinationFormat: destinationFormat
                )
            }
            sourceRect = geometry.sourceRect
            orientation = descriptor.orientation
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

    private func thumbnailMaximumPixelSize(
        for geometry: WIResolvedRender
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

    private func usesFullOrientedSource(
        _ geometry: WIResolvedRender
    ) -> Bool {
        let displaySize = descriptor.orientedPixelSize
        return geometry.sourceRect == Rect(
            x: 0,
            y: 0,
            width: Double(displaySize.width),
            height: Double(displaySize.height)
        )
    }

    private func rasterImage(
        _ image: CGImage,
        plan: WIImageRaster.Plan
    ) throws(WICompressError) -> CGImage {
        do {
            return try WIImageRaster.image(image, plan: plan)
        } catch {
            throw Self.map(error)
        }
    }

    private func rasterAlphaMode(
        destinationFormat: WIImageFormat
    ) -> WIImageRaster.AlphaMode {
        destinationFormat == .jpeg ? .opaque : .preserve
    }

    private func rasterJPEGBackground(
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

    private func rasterColorSpace(
        from colorSpace: WIResolvedOutputColorSpace
    ) -> WIImageRaster.OutputColorSpace {
        guard let target = colorSpace.target else {
            return .source
        }

        return .convert(target)
    }

    private static func mapSourceError(
        _ error: WIImageIO.Error
    ) -> WICompressError {
        switch error {
        case .invalidImageData:
            return .invalidImageData
        case .sourcePropertiesUnavailable,
             .invalidPixelSize,
             .pixelCountOverflow,
             .imageCreationFailed:
            return .imageInfoUnavailable
        case .thumbnailCreationFailed:
            return .thumbnailCreationFailed
        case .animatedSourceUnsupported(let frameCount):
            return .animatedSourceUnsupported(frameCount: frameCount)
        case .metadataCopyUnsupported:
            return .executionPlanUnavailable
        case .destinationCreationFailed(let typeIdentifier):
            return .destinationCreationFailed(
                .detected(from: typeIdentifier)
            )
        case .destinationFinalizationFailed(let typeIdentifier):
            return .encodeFailed(.detected(from: typeIdentifier))
        case .fileReadFailed(let url),
             .fileSizeUnavailable(let url):
            return .fileReadFailed(url)
        }
    }

    private static func mapExecutionError(
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
        case .metadataCopyUnsupported:
            return .executionPlanUnavailable
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
