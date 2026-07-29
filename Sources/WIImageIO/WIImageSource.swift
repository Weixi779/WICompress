//
//  WIImageSource.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO

package final class WIImageSource {
    package let byteCount: Int
    package let descriptor: WIImageDescriptor

    private let cgImageSource: CGImageSource

    package init(data: Data) throws(WIImageIOError) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw .invalidImageData
        }

        self.byteCount = data.count
        self.cgImageSource = source
        self.descriptor = try Self.inspect(source, byteCount: data.count)
    }

    package init(contentsOf url: URL) throws(WIImageIOError) {
        let byteCount = try Self.fileByteCount(for: url)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw .invalidImageData
        }

        self.byteCount = byteCount
        self.cgImageSource = source
        self.descriptor = try Self.inspect(source, byteCount: byteCount)
    }

    package func colorSpace() throws(WIImageIOError) -> WIImageColorSpace? {
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
        options: WIImageDecodeOptions = .init()
    ) throws(WIImageIOError) -> CGImage {
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
        options: WIThumbnailOptions
    ) throws(WIImageIOError) -> CGImage {
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
        options: WIImageCopyOptions = .init()
    ) throws(WIImageIOError) -> Data {
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

    private func validateStaticImage() throws(WIImageIOError) {
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

    private static func fileByteCount(for url: URL) throws(WIImageIOError) -> Int {
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
    ) throws(WIImageIOError) -> WIImageDescriptor {
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

        let pixelSize = try WIPixelSize(width: pixelWidth, height: pixelHeight)
        let orientation = properties.intValue(for: kCGImagePropertyOrientation) ?? 1
        let swapsDimensions = [5, 6, 7, 8].contains(orientation)
        let orientedPixelSize = try WIPixelSize(
            width: swapsDimensions ? pixelHeight : pixelWidth,
            height: swapsDimensions ? pixelWidth : pixelHeight
        )
        let typeIdentifier = CGImageSourceGetType(source) as String?

        return WIImageDescriptor(
            format: WIImageFormat(typeIdentifier: typeIdentifier),
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
            isSourceFormatDecodable: typeIdentifier.map(WIImageCapabilities.canDecode(typeIdentifier:)) ?? false,
            isSourceFormatWritable: typeIdentifier.map(WIImageCapabilities.canEncode(typeIdentifier:)) ?? false
        )
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
