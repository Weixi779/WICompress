//
//  Source.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import WIImageCore

package final class Source {
    package let byteCount: Int
    package let descriptor: Descriptor

    private let cgImageSource: CGImageSource

    package init(data: Data) throws(Error) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw .invalidImageData
        }

        self.byteCount = data.count
        self.cgImageSource = source
        self.descriptor = try Self.inspect(source, byteCount: data.count)
    }

    package init(contentsOf url: URL) throws(Error) {
        let byteCount = try Self.fileByteCount(for: url)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw .invalidImageData
        }

        self.byteCount = byteCount
        self.cgImageSource = source
        self.descriptor = try Self.inspect(source, byteCount: byteCount)
    }

    package func colorSpace() throws(Error) -> ColorSpace? {
        guard let image = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
            throw .imageCreationFailed
        }

        guard let colorSpace = image.colorSpace else {
            return nil
        }

        if let name = colorSpace.name as String? {
            if name == CGColorSpace.sRGB as String {
                return .sRGB
            }

            if name == CGColorSpace.displayP3 as String {
                return .displayP3
            }
        }

        guard colorSpace.model == .rgb, let iccData = colorSpace.copyICCData() else {
            return nil
        }

        return .iccProfile(iccData as Data)
    }

    package func image(
        options: DecodeOptions = .init()
    ) throws(Error) -> CGImage {
        try validateStaticImage()

        let properties: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: options.cacheImmediately
        ]
        guard let image = CGImageSourceCreateImageAtIndex(
            cgImageSource,
            0,
            properties as CFDictionary
        ) else {
            throw .imageCreationFailed
        }

        return image
    }

    package func thumbnail(
        options: ThumbnailOptions
    ) throws(Error) -> CGImage {
        try validateStaticImage()

        var properties: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: options.appliesOrientationTransform,
            kCGImageSourceShouldCacheImmediately: options.cacheImmediately
        ]
        if let maximumPixelSize = options.maximumPixelSize {
            properties[kCGImageSourceThumbnailMaxPixelSize] = maximumPixelSize
        }

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            cgImageSource,
            0,
            properties as CFDictionary
        ) else {
            throw .thumbnailCreationFailed
        }

        return image
    }

    package func copy(
        `as` typeIdentifier: String,
        options: CopyOptions = .init()
    ) throws(Error) -> Data {
        try validateStaticImage()

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw .destinationCreationFailed(typeIdentifier)
        }

        var properties: [CFString: Any] = [:]
        if let maximumPixelSize = options.maximumPixelSize {
            properties[kCGImageDestinationImageMaxPixelSize] = maximumPixelSize
        }
        if let compressionQuality = options.compressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        }

        CGImageDestinationAddImageFromSource(
            destination,
            cgImageSource,
            0,
            properties as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            throw .destinationFinalizationFailed(typeIdentifier)
        }

        return outputData as Data
    }

    private func validateStaticImage() throws(Error) {
        guard descriptor.frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: descriptor.frameCount)
        }
    }

    func preservedMetadataProperties() -> [CFString: Any] {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            cgImageSource,
            0,
            nil
        ) as? [CFString: Any] else {
            return [:]
        }

        return Self.metadataKeys.reduce(into: [:]) { result, key in
            if let value = properties[key] {
                result[key] = value
            }
        }
    }

    private static func fileByteCount(for url: URL) throws(Error) -> Int {
        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        } catch {
            throw .fileReadFailed(url)
        }

        if let fileSize = resourceValues.fileSize, fileSize >= 0 {
            return fileSize
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw .fileReadFailed(url)
        }

        guard
            let fileSize = attributes[.size] as? NSNumber,
            fileSize.intValue >= 0
        else {
            throw .fileSizeUnavailable(url)
        }

        return fileSize.intValue
    }

    private static func inspect(
        _ source: CGImageSource,
        byteCount: Int
    ) throws(Error) -> Descriptor {
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw .invalidImageData
        }

        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = properties.intValue(for: kCGImagePropertyPixelWidth),
            let pixelHeight = properties.intValue(for: kCGImagePropertyPixelHeight)
        else {
            throw .sourcePropertiesUnavailable
        }

        let pixelSize = try makePixelSize(
            width: pixelWidth,
            height: pixelHeight
        )
        guard let orientation = Orientation(
            rawValue: properties.intValue(
                for: kCGImagePropertyOrientation
            ) ?? Orientation.up.rawValue
        ) else {
            throw .sourcePropertiesUnavailable
        }
        let orientedPixelSize = try makePixelSize(
            width: orientation.swapsDimensions ? pixelHeight : pixelWidth,
            height: orientation.swapsDimensions ? pixelWidth : pixelHeight
        )
        let typeIdentifier = CGImageSourceGetType(source) as String?

        return Descriptor(
            format: ImageFormat(typeIdentifier: typeIdentifier),
            typeIdentifier: typeIdentifier,
            byteCount: byteCount,
            pixelSize: pixelSize,
            orientedPixelSize: orientedPixelSize,
            orientation: orientation,
            frameCount: frameCount,
            hasAlpha: properties.boolValue(for: kCGImagePropertyHasAlpha),
            hasMetadata: hasStrippableMetadata(in: properties),
            hasGPS: properties.dictionaryExists(for: kCGImagePropertyGPSDictionary),
            hasGainMap: hasGainMap(in: source),
            isSourceFormatDecodable: typeIdentifier.map(Capabilities.canDecode(typeIdentifier:)) ?? false,
            isSourceFormatWritable: typeIdentifier.map(Capabilities.canEncode(typeIdentifier:)) ?? false
        )
    }

    private static func makePixelSize(
        width: Int,
        height: Int
    ) throws(Error) -> PixelSize {
        do {
            return try PixelSize(width: width, height: height)
        } catch {
            switch error {
            case .invalidDimensions:
                throw .invalidPixelSize(width: width, height: height)
            case .pixelCountOverflow:
                throw .pixelCountOverflow(width: width, height: height)
            }
        }
    }

    private static func hasStrippableMetadata(in properties: [CFString: Any]) -> Bool {
        // Color profiles and pixel geometry are display semantics, not privacy metadata.
        return metadataKeys.contains { properties.dictionaryExists(for: $0) }
    }

    private static var metadataKeys: [CFString] {
        [
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
    }

    private static func hasGainMap(in source: CGImageSource) -> Bool {
        if #available(iOS 14.1, macOS 11.0, *) {
            return CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source,
                0,
                kCGImageAuxiliaryDataTypeHDRGainMap
            ) != nil
        }

        return false
    }
}

private extension Dictionary where Key == CFString, Value == Any {
    func intValue(for key: CFString) -> Int? {
        if let value = self[key] as? Int {
            return value
        }

        if let value = self[key] as? NSNumber {
            return value.intValue
        }

        return nil
    }

    func boolValue(for key: CFString) -> Bool? {
        if let value = self[key] as? Bool {
            return value
        }

        if let value = self[key] as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    func dictionaryExists(for key: CFString) -> Bool {
        guard let dictionary = self[key] as? [AnyHashable: Any] else {
            return false
        }

        return !dictionary.isEmpty
    }
}
