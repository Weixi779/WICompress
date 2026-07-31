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
import UniformTypeIdentifiers
import WIImageDomain

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

    package func colorSpace() throws(Error) -> WIColorSpace? {
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
        `as` type: UTType,
        options: CopyOptions = .init()
    ) throws(Error) -> Data {
        try validateStaticImage()

        let removedMetadata = descriptor.metadata.subtracting(
            options.metadata
        )
        guard
            !descriptor.hasUnmodeledMetadata
                || options.metadata.preservesUnmodeledMetadata
        else {
            throw .metadataCopyUnsupported
        }
        guard removedMetadata.isEmpty else {
            guard
                removedMetadata == .gps,
                options.maximumPixelSize == nil,
                options.compressionQuality == nil,
                descriptor.type == type
            else {
                throw .metadataCopyUnsupported
            }

            return try copyExcludingGPS(as: type)
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw .destinationCreationFailed(type)
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
            throw .destinationFinalizationFailed(type)
        }

        return outputData as Data
    }

    package func canCopy(
        `as` type: UTType,
        keeping metadata: WIImageMetadataOptions,
        compressionQuality: Double?
    ) -> Bool {
        guard
            !descriptor.hasUnmodeledMetadata
                || metadata.preservesUnmodeledMetadata
        else {
            return false
        }

        let removedMetadata = descriptor.metadata.subtracting(metadata)
        if removedMetadata.isEmpty {
            return true
        }

        return removedMetadata == .gps
            && compressionQuality == nil
            && descriptor.type == type
    }

    private func validateStaticImage() throws(Error) {
        guard descriptor.frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: descriptor.frameCount)
        }
    }

    func metadataProperties(
        keeping options: WIImageMetadataOptions
    ) -> [CFString: Any] {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            cgImageSource,
            0,
            nil
        ) as? [CFString: Any] else {
            return [:]
        }

        return Self.metadataProperties(
            in: properties,
            keeping: options
        )
    }

    private func copyExcludingGPS(
        as type: UTType
    ) throws(Error) -> Data {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(
            cgImageSource,
            0,
            nil
        ) else {
            throw .sourcePropertiesUnavailable
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw .destinationCreationFailed(type)
        }

        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: true,
            kCGImageMetadataShouldExcludeGPS: true
        ]
        guard CGImageDestinationCopyImageSource(
            destination,
            cgImageSource,
            options as CFDictionary,
            nil
        ) else {
            throw .destinationFinalizationFailed(type)
        }

        return outputData as Data
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
        let type = (CGImageSourceGetType(source) as String?)
            .flatMap(UTType.init)

        return Descriptor(
            type: type,
            byteCount: byteCount,
            pixelSize: pixelSize,
            orientation: orientation,
            frameCount: frameCount,
            hasAlpha: properties.boolValue(for: kCGImagePropertyHasAlpha),
            metadata: metadataOptions(in: properties),
            hasUnmodeledMetadata: hasUnmodeledMetadata(
                in: source,
                properties: properties
            ),
            hasGainMap: hasGainMap(in: source)
        )
    }

    private static func makePixelSize(
        width: Int,
        height: Int
    ) throws(Error) -> WIPixelSize {
        guard width > 0, height > 0 else {
            throw .invalidPixelSize(width: width, height: height)
        }

        let (_, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw .pixelCountOverflow(width: width, height: height)
        }

        return WIPixelSize(validWidth: width, height: height)
    }

    static func metadataOptions(
        in properties: [CFString: Any]
    ) -> WIImageMetadataOptions {
        var options: WIImageMetadataOptions = []
        for option in WIImageMetadataOptions.all.singleOptions {
            if !metadataProperties(
                in: properties,
                keeping: option
            ).isEmpty {
                options.insert(option)
            }
        }
        return options
    }

    static func metadataProperties(
        in properties: [CFString: Any],
        keeping options: WIImageMetadataOptions
    ) -> [CFString: Any] {
        var metadata: [CFString: Any] = metadataKeys(
            for: options
        ).reduce(into: [:]) { result, key in
            if
                properties.dictionaryExists(for: key),
                let value = properties[key]
            {
                result[key] = value
            }
        }

        if options.contains(.makerNotes) {
            if
                !options.contains(.exif),
                let makerNote = exifMakerNote(in: properties)
            {
                metadata[kCGImagePropertyExifDictionary] = [
                    kCGImagePropertyExifMakerNote: makerNote
                ]
            }
        } else {
            remove(
                kCGImagePropertyExifMakerNote,
                from: kCGImagePropertyExifDictionary,
                in: &metadata
            )
        }

        removeDisplayOrientation(from: &metadata)
        return metadata
    }

    private static func metadataKeys(
        for options: WIImageMetadataOptions
    ) -> [CFString] {
        var keys: [CFString] = []
        if options.contains(.exif) {
            keys.append(kCGImagePropertyExifDictionary)
            keys.append(kCGImagePropertyExifAuxDictionary)
        }
        if options.contains(.gps) {
            keys.append(kCGImagePropertyGPSDictionary)
        }
        if options.contains(.iptc) {
            keys.append(kCGImagePropertyIPTCDictionary)
        }
        if options.contains(.tiff) {
            keys.append(kCGImagePropertyTIFFDictionary)
        }
        if options.contains(.makerNotes) {
            keys.append(kCGImagePropertyMakerAppleDictionary)
            keys.append(kCGImagePropertyMakerCanonDictionary)
            keys.append(kCGImagePropertyMakerNikonDictionary)
            keys.append(kCGImagePropertyMakerMinoltaDictionary)
            keys.append(kCGImagePropertyMakerFujiDictionary)
            keys.append(kCGImagePropertyMakerOlympusDictionary)
            keys.append(kCGImagePropertyMakerPentaxDictionary)
        }
        return keys
    }

    private static func exifMakerNote(
        in properties: [CFString: Any]
    ) -> Any? {
        guard
            let exif = properties[kCGImagePropertyExifDictionary]
                as? [AnyHashable: Any]
        else {
            return nil
        }

        return exif[kCGImagePropertyExifMakerNote]
    }

    private static func hasUnmodeledMetadata(
        in source: CGImageSource,
        properties: [CFString: Any]
    ) -> Bool {
        if properties.dictionaryExists(for: kCGImageProperty8BIMDictionary)
            || hasPNGTextMetadata(in: properties) {
            return true
        }

        guard
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
            let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
        else {
            return false
        }

        return tags.contains { tag in
            guard let namespace = CGImageMetadataTagCopyNamespace(tag) as String? else {
                return false
            }
            return !recognizedMetadataNamespaces.contains(namespace)
        }
    }

    private static func hasPNGTextMetadata(
        in properties: [CFString: Any]
    ) -> Bool {
        guard
            let png = properties[kCGImagePropertyPNGDictionary]
                as? [AnyHashable: Any]
        else {
            return false
        }

        let textKeys: [CFString] = [
            kCGImagePropertyPNGAuthor,
            kCGImagePropertyPNGComment,
            kCGImagePropertyPNGCopyright,
            kCGImagePropertyPNGCreationTime,
            kCGImagePropertyPNGDescription,
            kCGImagePropertyPNGDisclaimer,
            kCGImagePropertyPNGModificationTime,
            kCGImagePropertyPNGSoftware,
            kCGImagePropertyPNGSource,
            kCGImagePropertyPNGTitle,
            kCGImagePropertyPNGWarning
        ]
        return textKeys.contains { png[$0] != nil }
    }

    // ImageIO synthesizes technical tags in its private namespace from ordinary
    // image properties, so their presence does not imply independent metadata.
    private static let recognizedMetadataNamespaces: Set<String> = [
        kCGImageMetadataNamespaceExif as String,
        kCGImageMetadataNamespaceExifAux as String,
        kCGImageMetadataNamespaceExifEX as String,
        kCGImageMetadataNamespaceIPTCCore as String,
        kCGImageMetadataNamespaceIPTCExtension as String,
        kCGImageMetadataNamespaceTIFF as String,
        "http://ns.apple.com/ImageIO/1.0/"
    ]

    private static func removeDisplayOrientation(
        from metadata: inout [CFString: Any]
    ) {
        remove(
            kCGImagePropertyTIFFOrientation,
            from: kCGImagePropertyTIFFDictionary,
            in: &metadata
        )
        remove(
            kCGImagePropertyIPTCImageOrientation,
            from: kCGImagePropertyIPTCDictionary,
            in: &metadata
        )
    }

    private static func remove(
        _ property: CFString,
        from dictionaryKey: CFString,
        in metadata: inout [CFString: Any]
    ) {
        guard var dictionary = metadata[dictionaryKey] as? [AnyHashable: Any] else {
            return
        }

        dictionary.removeValue(forKey: property)
        if dictionary.isEmpty {
            metadata.removeValue(forKey: dictionaryKey)
        } else {
            metadata[dictionaryKey] = dictionary
        }
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

private extension WIImageMetadataOptions {
    var singleOptions: [Self] {
        [.exif, .gps, .iptc, .tiff, .makerNotes].filter(contains)
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
