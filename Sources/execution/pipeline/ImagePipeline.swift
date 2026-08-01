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
import WICompressDomain
import WIImageDomain
import WIImageIO
import WIImageRaster

package final class ImagePipeline {
    enum Input {
        case data(Data)
        case file(URL)
    }

    let input: Input
    let reader: WIImageIO.Reader

    var descriptor: WIImageIO.Descriptor {
        reader.descriptor
    }

    var byteCount: Int {
        descriptor.byteCount
    }

    convenience init(data: Data) throws(WICompressError) {
        try self.init(
            input: .data(data),
            reader: Self.imageIO { () throws(WIImageIO.Error) in
                try WIImageIO.read(data)
            }
        )
    }

    convenience init(contentsOf url: URL) throws(WICompressError) {
        try self.init(
            input: .file(url),
            reader: Self.imageIO { () throws(WIImageIO.Error) in
                try WIImageIO.read(contentsOf: url)
            }
        )
    }

    private init(
        input: Input,
        reader: WIImageIO.Reader
    ) throws(WICompressError) {
        guard reader.descriptor.frameCount == 1 else {
            throw .animatedSourceUnsupported(
                frameCount: reader.descriptor.frameCount
            )
        }

        self.input = input
        self.reader = reader
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
        try Self.imageIO { () throws(WIImageIO.Error) in
            try reader.colorSpace()
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
        let outputDescriptor = try Self.imageIO { () throws(WIImageIO.Error) in
            try WIImageIO.read(data).descriptor
        }

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

    func copyFromSource(
        output: ImageDestination,
        metadata: WIImageMetadataOptions,
        quality: Double?
    ) throws(WICompressError) -> Data {
        try copyFromSource(
            as: output.destinationType,
            metadata: metadata,
            quality: quality
        )
    }

    func renderAndEncode(
        geometry: RenderGeometry,
        output: ImageDestination,
        metadata: WIImageMetadataOptions,
        quality: Double?
    ) throws(WICompressError) -> Data {
        let image = try render(
            geometry: geometry,
            output: output
        )
        return try encodeRendered(
            image,
            output: output,
            metadata: metadata,
            quality: quality
        )
    }

    func render(
        geometry: RenderGeometry,
        output: ImageDestination
    ) throws(WICompressError) -> CGImage {
        return try render(
            geometry: geometry,
            destinationFormat: output.destinationFormat,
            jpegBackground: output.jpegBackground,
            outputColorSpace: output.colorSpace
        )
    }

    func encodeRendered(
        _ image: CGImage,
        output: ImageDestination,
        metadata: WIImageMetadataOptions,
        quality: Double?
    ) throws(WICompressError) -> Data {
        try encodeRendered(
            image,
            as: output.destinationType,
            metadata: metadata,
            quality: quality
        )
    }

    private func copyFromSource(
        as destinationType: UTType,
        metadata: WIImageMetadataOptions,
        quality: Double?
    ) throws(WICompressError) -> Data {
        let options = WIImageIO.CopyOptions(
            compressionQuality: quality,
            metadata: metadata
        )
        return try Self.imageIO { () throws(WIImageIO.Error) in
            try reader.copy(
                as: destinationType,
                options: options
            )
        }
    }

    private func encodeRendered(
        _ image: CGImage,
        as destinationType: UTType,
        metadata: WIImageMetadataOptions,
        quality: Double?
    ) throws(WICompressError) -> Data {
        let options = WIImageIO.EncodeOptions(
            compressionQuality: quality,
            metadata: metadata
        )
        return try Self.imageIO { () throws(WIImageIO.Error) in
            try reader
                .frame(image)
                .encode(
                    as: destinationType,
                    options: options
                )
        }
    }

    private func render(
        geometry: RenderGeometry,
        destinationFormat: WIImageFormat,
        jpegBackground: WIJPEGBackground?,
        outputColorSpace: DestinationColorSpace
    ) throws(WICompressError) -> CGImage {
        let sourceImage: CGImage
        let sourceRect: Rect
        let orientation: WIImageOrientation
        if usesFullOrientedSource(geometry) {
            if let maximumPixelSize = thumbnailMaximumPixelSize(
                for: geometry
            ) {
                sourceImage = try decodedThumbnail(
                    maximumPixelSize: maximumPixelSize
                )
                sourceRect = Rect(
                    x: 0,
                    y: 0,
                    width: Double(sourceImage.width),
                    height: Double(sourceImage.height)
                )
                orientation = .up
            } else {
                sourceImage = try decodedImage()
                sourceRect = geometry.sourceRect
                orientation = descriptor.orientation
            }
        } else {
            sourceImage = try decodedImage()
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

    private func decodedImage() throws(WICompressError) -> CGImage {
        try Self.imageIO { () throws(WIImageIO.Error) in
            try reader.image().image
        }
    }

    private func decodedThumbnail(
        maximumPixelSize: Int
    ) throws(WICompressError) -> CGImage {
        let options = WIImageIO.ThumbnailOptions(
            maximumPixelSize: maximumPixelSize
        )
        return try Self.imageIO { () throws(WIImageIO.Error) in
            try reader.thumbnail(options: options).image
        }
    }

    private func thumbnailMaximumPixelSize(
        for geometry: RenderGeometry
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
        _ geometry: RenderGeometry
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
        from colorSpace: DestinationColorSpace
    ) -> WIImageRaster.OutputColorSpace {
        guard let target = colorSpace.target else {
            return .source
        }

        return .convert(target)
    }

    private static func map(
        _ error: WIImageRaster.Error
    ) -> WICompressError {
        switch error {
        case .invalidSourceRect,
             .invalidDestinationRect,
             .sourceRectOutOfBounds:
            return .imageRenderingFailed
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
            return .imageRenderingFailed
        }
    }

    private static func imageIO<Value>(
        _ operation: () throws(WIImageIO.Error) -> Value
    ) throws(WICompressError) -> Value {
        do {
            return try operation()
        } catch {
            throw map(error)
        }
    }

    private static func map(
        _ error: WIImageIO.Error
    ) -> WICompressError {
        switch error {
        case .fileReadFailed(let url):
            return .fileReadFailed(url)
        case .invalidImageData:
            return .invalidImageData
        case .imageInfoUnavailable:
            return .imageInfoUnavailable
        case .animatedSourceUnsupported(let frameCount):
            return .animatedSourceUnsupported(frameCount: frameCount)
        case .imageDecodeFailed:
            return .imageDecodeFailed
        case .metadataCopyUnsupported(let type),
             .imageEncodeFailed(let type):
            return .imageEncodeFailed(.detected(from: type))
        }
    }
}

struct RenderGeometry: Sendable, Equatable {
    let sourceRect: Rect
    let canvasSize: WIPixelSize
    let destinationRect: Rect
    let canvasBackground: WIColor?
}
