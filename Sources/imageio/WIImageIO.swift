//
//  WIImageIO.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/31.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WIImageDomain

/// ImageIO-backed inspection, decoding, transcoding, and encoding operations.
public enum WIImageIO {}

// MARK: - Capabilities

extension WIImageIO {
    /// Whether the current ImageIO runtime can decode the supplied type.
    public static func canDecode(_ type: UTType) -> Bool {
        readableTypes.contains(type)
    }

    /// Whether the current ImageIO runtime can encode the supplied type.
    public static func canEncode(_ type: UTType) -> Bool {
        writableTypes.contains(type)
    }

    private static let readableTypes: Set<UTType> = {
        guard let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] else {
            return []
        }

        return Set(identifiers.compactMap(UTType.init))
    }()

    private static let writableTypes: Set<UTType> = {
        guard let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] else {
            return []
        }

        return Set(identifiers.compactMap(UTType.init))
    }()
}

// MARK: - Inspection

extension WIImageIO {
    /// Opens encoded image data for inspection and pixel operations.
    public static func read(_ data: Data) throws(WIImageIO.Error) -> Reader {
        let source = try imageSource(data)
        return Reader(
            source: source,
            descriptor: try descriptor(source, byteCount: data.count)
        )
    }

    /// Opens an encoded image file without loading its complete bytes.
    public static func read(contentsOf url: URL) throws(WIImageIO.Error) -> Reader {
        let (source, byteCount) = try fileImageSource(contentsOf: url)
        return Reader(
            source: source,
            descriptor: try descriptor(source, byteCount: byteCount)
        )
    }

    /// Inspects encoded image data without decoding its pixels.
    public static func inspect(_ data: Data) throws(WIImageIO.Error) -> Descriptor {
        try read(data).descriptor
    }

    /// Inspects an encoded image file without loading its complete bytes.
    public static func inspect(contentsOf url: URL) throws(WIImageIO.Error) -> Descriptor {
        try read(contentsOf: url).descriptor
    }

    static func imageSource(_ data: Data) throws(WIImageIO.Error) -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw .invalidImageData
        }
        return source
    }

    static func fileImageSource(
        contentsOf url: URL
    ) throws(WIImageIO.Error) -> (source: CGImageSource, byteCount: Int) {
        let byteCount = try fileByteCount(for: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw .invalidImageData
        }
        return (source, byteCount)
    }

    static func validateStaticImage(_ source: CGImageSource) throws(WIImageIO.Error) {
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: frameCount)
        }
    }

    static func descriptor(
        _ source: CGImageSource,
        byteCount: Int
    ) throws(WIImageIO.Error) -> Descriptor {
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw .invalidImageData
        }

        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any],
            let pixelWidth = properties.intValue(
                for: kCGImagePropertyPixelWidth
            ),
            let pixelHeight = properties.intValue(
                for: kCGImagePropertyPixelHeight
            )
        else {
            throw .imageInfoUnavailable
        }

        let pixelSize = try pixelSize(
            width: pixelWidth,
            height: pixelHeight
        )
        guard
            let orientation = WIImageOrientation(
                rawValue: properties.intValue(
                    for: kCGImagePropertyOrientation
                ) ?? WIImageOrientation.up.rawValue
            )
        else {
            throw .imageInfoUnavailable
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

    private static func pixelSize(
        width: Int,
        height: Int
    ) throws(WIImageIO.Error) -> WIPixelSize {
        guard width > 0, height > 0 else {
            throw .imageInfoUnavailable
        }

        let (_, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw .imageInfoUnavailable
        }

        return WIPixelSize(validWidth: width, height: height)
    }

    private static func fileByteCount(for url: URL) throws(WIImageIO.Error) -> Int {
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
            attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
        } catch {
            throw .fileReadFailed(url)
        }

        guard
            let fileSize = attributes[.size] as? NSNumber,
            fileSize.intValue >= 0
        else {
            throw .fileReadFailed(url)
        }

        return fileSize.intValue
    }
}

extension Dictionary where Key == CFString, Value == Any {
    fileprivate func intValue(for key: CFString) -> Int? {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    fileprivate func boolValue(for key: CFString) -> Bool? {
        if let value = self[key] as? Bool {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.boolValue
        }
        return nil
    }
}

// MARK: - Decoding

extension WIImageIO {
    static func colorSpace(
        _ source: CGImageSource
    ) throws(WIImageIO.Error) -> WIColorSpace? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw .imageInfoUnavailable
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

        guard colorSpace.model == .rgb,
            let iccData = colorSpace.copyICCData()
        else {
            return nil
        }
        return .iccProfile(iccData as Data)
    }

    static func image(
        _ source: CGImageSource,
        options: DecodeOptions
    ) throws(WIImageIO.Error) -> CGImage {
        try validateStaticImage(source)

        let properties: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: options.cacheImmediately
        ]
        guard
            let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                properties as CFDictionary
            )
        else {
            throw .imageDecodeFailed
        }
        return image
    }

    static func thumbnail(
        _ source: CGImageSource,
        options: ThumbnailOptions
    ) throws(WIImageIO.Error) -> CGImage {
        try validateStaticImage(source)

        var properties: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: options.appliesOrientationTransform,
            kCGImageSourceShouldCacheImmediately: options.cacheImmediately,
        ]
        if let maximumPixelSize = options.maximumPixelSize {
            properties[kCGImageSourceThumbnailMaxPixelSize] = maximumPixelSize
        }

        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                properties as CFDictionary
            )
        else {
            throw .imageDecodeFailed
        }
        return image
    }
}

// MARK: - Metadata

extension WIImageIO {
    static func metadataProvenance(
        _ source: CGImageSource
    ) -> MetadataProvenance? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any]
        else {
            return nil
        }
        return MetadataProvenance(sourceProperties: properties)
    }

    static func metadataProperties(
        _ source: CGImageSource,
        keeping options: WIImageMetadataOptions
    ) -> [CFString: Any] {
        metadataProvenance(source)?.properties(keeping: options) ?? [:]
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
            if properties.dictionaryExists(for: key),
                let value = properties[key]
            {
                result[key] = value
            }
        }

        if options.contains(.makerNotes) {
            if !options.contains(.exif),
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

    private static func hasUnmodeledMetadata(
        in source: CGImageSource,
        properties: [CFString: Any]
    ) -> Bool {
        if properties.dictionaryExists(for: kCGImageProperty8BIMDictionary)
            || hasPNGTextMetadata(in: properties)
        {
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
            kCGImagePropertyPNGWarning,
        ]
        return textKeys.contains { png[$0] != nil }
    }

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

    // ImageIO synthesizes technical tags in its private namespace from ordinary
    // image properties, so their presence does not imply independent metadata.
    private static let recognizedMetadataNamespaces: Set<String> = [
        kCGImageMetadataNamespaceExif as String,
        kCGImageMetadataNamespaceExifAux as String,
        kCGImageMetadataNamespaceExifEX as String,
        kCGImageMetadataNamespaceIPTCCore as String,
        kCGImageMetadataNamespaceIPTCExtension as String,
        kCGImageMetadataNamespaceTIFF as String,
        "http://ns.apple.com/ImageIO/1.0/",
    ]
}

extension WIImageMetadataOptions {
    fileprivate var singleOptions: [Self] {
        [.exif, .gps, .iptc, .tiff, .makerNotes].filter(contains)
    }
}

extension Dictionary where Key == CFString, Value == Any {
    fileprivate func dictionaryExists(for key: CFString) -> Bool {
        guard let dictionary = self[key] as? [AnyHashable: Any] else {
            return false
        }
        return !dictionary.isEmpty
    }
}

// MARK: - Transcoding

extension WIImageIO {
    static func canTranscode(
        _ descriptor: Descriptor,
        `as` type: UTType,
        options: TranscodeOptions
    ) -> Bool {
        guard
            descriptor.frameCount == 1,
            canEncode(type),
            !descriptor.hasUnmodeledMetadata
                || options.metadata.preservesUnmodeledMetadata
        else {
            return false
        }

        let removedMetadata = descriptor.metadata.subtracting(options.metadata)
        if removedMetadata.isEmpty {
            return true
        }

        return removedMetadata == .gps
            && options.maximumPixelSize == nil
            && options.compressionQuality == nil
            && descriptor.type == type
    }

    static func transcode(
        _ source: CGImageSource,
        descriptor: Descriptor,
        as type: UTType,
        options: TranscodeOptions
    ) throws(WIImageIO.Error) -> Data {
        try validateStaticImage(source)

        let removedMetadata = descriptor.metadata.subtracting(options.metadata)
        guard
            !descriptor.hasUnmodeledMetadata
                || options.metadata.preservesUnmodeledMetadata
        else {
            throw .metadataTranscodeUnsupported(type)
        }
        guard removedMetadata.isEmpty else {
            guard
                removedMetadata == .gps,
                options.maximumPixelSize == nil,
                options.compressionQuality == nil,
                descriptor.type == type
            else {
                throw .metadataTranscodeUnsupported(type)
            }
            return try copyExcludingGPS(source, as: type)
        }

        var properties: [CFString: Any] = [:]
        if let maximumPixelSize = options.maximumPixelSize {
            properties[kCGImageDestinationImageMaxPixelSize] = maximumPixelSize
        }
        if let compressionQuality = options.compressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        }

        return try encodedData(as: type) { destination in
            CGImageDestinationAddImageFromSource(
                destination,
                source,
                0,
                properties as CFDictionary
            )
        }
    }

    private static func copyExcludingGPS(
        _ source: CGImageSource,
        as type: UTType
    ) throws(WIImageIO.Error) -> Data {
        guard
            let metadata = CGImageSourceCopyMetadataAtIndex(
                source,
                0,
                nil
            )
        else {
            throw .imageInfoUnavailable
        }

        let outputData = NSMutableData()
        let destination = try destination(as: type, writingTo: outputData)

        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: true,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        guard
            CGImageDestinationCopyImageSource(
                destination,
                source,
                options as CFDictionary,
                nil
            )
        else {
            throw .imageEncodeFailed(type)
        }
        return outputData as Data
    }
}

// MARK: - Encoding

extension WIImageIO {
    static func encode(
        _ image: CGImage,
        as type: UTType,
        options: EncodeOptions,
        metadata: [CFString: Any],
        orientation: WIImageOrientation = .up
    ) throws(WIImageIO.Error) -> Data {
        var properties = metadata
        if let compressionQuality = options.compressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        }

        properties[kCGImagePropertyOrientation] = orientation.rawValue
        return try encodedData(as: type) { destination in
            CGImageDestinationAddImage(
                destination,
                image,
                properties as CFDictionary
            )
        }
    }
}

// MARK: - Private Helpers

extension WIImageIO {
    private static func encodedData(
        as type: UTType,
        addingImage: (CGImageDestination) -> Void
    ) throws(WIImageIO.Error) -> Data {
        let outputData = NSMutableData()
        let destination = try destination(as: type, writingTo: outputData)
        addingImage(destination)

        guard CGImageDestinationFinalize(destination) else {
            throw .imageEncodeFailed(type)
        }
        return outputData as Data
    }

    private static func destination(
        as type: UTType,
        writingTo data: NSMutableData
    ) throws(WIImageIO.Error) -> CGImageDestination {
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                type.identifier as CFString,
                1,
                nil
            )
        else {
            throw .imageEncodeFailed(type)
        }
        return destination
    }
}
