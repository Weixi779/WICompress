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
@_exported public import WIImageDomain

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

    private static let readableTypes = supportedTypes(CGImageSourceCopyTypeIdentifiers())

    private static let writableTypes = supportedTypes(CGImageDestinationCopyTypeIdentifiers())

    private static func supportedTypes(_ identifiers: CFArray) -> Set<UTType> {
        guard let identifiers = identifiers as? [String] else {
            return []
        }

        return Set(identifiers.compactMap(UTType.init))
    }
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
        let (source, byteCount) = try imageSource(contentsOf: url)
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

    private static func imageSource(_ data: Data) throws(WIImageIO.Error) -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw .invalidImageData
        }
        return source
    }

    private static func imageSource(
        contentsOf url: URL
    ) throws(WIImageIO.Error) -> (source: CGImageSource, byteCount: Int) {
        let byteCount = try fileByteCount(for: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw .invalidImageData
        }
        return (source, byteCount)
    }

    private static func descriptor(
        _ source: CGImageSource,
        byteCount: Int
    ) throws(WIImageIO.Error) -> Descriptor {
        let frameCount = source.frameCount
        guard frameCount > 0 else {
            throw .invalidImageData
        }

        guard let properties = source.properties(at: 0) else {
            throw .imageInfoUnavailable
        }

        guard
            let pixelWidth = properties.intValue(for: kCGImagePropertyPixelWidth),
            let pixelHeight = properties.intValue(for: kCGImagePropertyPixelHeight)
        else {
            throw .imageInfoUnavailable
        }

        let pixelSize = try pixelSize(width: pixelWidth, height: pixelHeight)
        let orientationValue = properties.intValue(for: kCGImagePropertyOrientation) ?? WIImageOrientation.up.rawValue
        guard let orientation = WIImageOrientation(rawValue: orientationValue) else {
            throw .imageInfoUnavailable
        }

        return Descriptor(
            type: source.type,
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

// MARK: - Decoding

extension WIImageIO {
    static func colorSpace(
        _ source: CGImageSource
    ) throws(WIImageIO.Error) -> WIColorSpace? {
        guard let image = source.image(at: 0) else {
            throw .imageInfoUnavailable
        }

        guard let colorSpace = image.colorSpace else {
            return nil
        }

        if colorSpace.name == CGColorSpace.sRGB {
            return .sRGB
        }
        if colorSpace.name == CGColorSpace.displayP3 {
            return .displayP3
        }

        guard colorSpace.model == .rgb else {
            return nil
        }
        guard let iccData = colorSpace.copyICCData() else {
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
        guard let image = source.image(at: 0, options: properties) else {
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

        guard let image = source.thumbnail(at: 0, options: properties) else {
            throw .imageDecodeFailed
        }
        return image
    }
}

// MARK: - Transcoding

extension WIImageIO {
    private enum TranscodeMethod {
        case addImageFromSource
        case copyImageSourceExcludingGPS
    }

    static func canTranscode(
        _ descriptor: Descriptor,
        `as` type: UTType,
        options: TranscodeOptions
    ) -> Bool {
        guard descriptor.frameCount == 1 else {
            return false
        }
        guard canEncode(type) else {
            return false
        }

        return transcodeMethod(for: descriptor, as: type, options: options) != nil
    }

    static func transcode(
        _ source: CGImageSource,
        descriptor: Descriptor,
        as type: UTType,
        options: TranscodeOptions
    ) throws(WIImageIO.Error) -> Data {
        try validateStaticImage(source)

        guard let method = transcodeMethod(for: descriptor, as: type, options: options) else {
            throw .metadataTranscodeUnsupported(type)
        }

        switch method {
        case .addImageFromSource:
            return try addImageFromSource(source, as: type, options: options)
        case .copyImageSourceExcludingGPS:
            return try copyImageSourceExcludingGPS(source, as: type)
        }
    }

    private static func transcodeMethod(
        for descriptor: Descriptor,
        as type: UTType,
        options: TranscodeOptions
    ) -> TranscodeMethod? {
        let containsUnmodeledMetadata = descriptor.hasUnmodeledMetadata
        let preservesUnmodeledMetadata = options.metadata.preservesUnmodeledMetadata
        guard !containsUnmodeledMetadata || preservesUnmodeledMetadata else {
            return nil
        }

        let removedMetadata = descriptor.metadata.subtracting(options.metadata)
        if removedMetadata.isEmpty {
            return .addImageFromSource
        }

        guard removedMetadata == .gps else {
            return nil
        }
        guard options.maximumPixelSize == nil else {
            return nil
        }
        guard options.compressionQuality == nil else {
            return nil
        }
        guard descriptor.type == type else {
            return nil
        }

        return .copyImageSourceExcludingGPS
    }

    private static func addImageFromSource(
        _ source: CGImageSource,
        as type: UTType,
        options: TranscodeOptions
    ) throws(WIImageIO.Error) -> Data {
        var properties: [CFString: Any] = [:]
        if let maximumPixelSize = options.maximumPixelSize {
            properties[kCGImageDestinationImageMaxPixelSize] = maximumPixelSize
        }
        if let compressionQuality = options.compressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        }

        return try encodedData(as: type) { destination in
            destination.addImage(
                from: source,
                at: 0,
                properties: properties
            )
        }
    }

    private static func copyImageSourceExcludingGPS(
        _ source: CGImageSource,
        as type: UTType
    ) throws(WIImageIO.Error) -> Data {
        guard let metadata = source.metadata(at: 0) else {
            throw .imageInfoUnavailable
        }

        let outputData = NSMutableData()
        let destination = try destination(as: type, writingTo: outputData)

        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: true,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        guard destination.copyImageSource(source, options: options) else {
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
            destination.addImage(image, properties: properties)
        }
    }
}

// MARK: - Private Helpers

extension WIImageIO {
    private static func validateStaticImage(_ source: CGImageSource) throws(WIImageIO.Error) {
        let frameCount = source.frameCount
        guard frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: frameCount)
        }
    }

    private static func encodedData(
        as type: UTType,
        addingImage: (CGImageDestination) -> Void
    ) throws(WIImageIO.Error) -> Data {
        let outputData = NSMutableData()
        let destination = try destination(as: type, writingTo: outputData)
        addingImage(destination)

        guard destination.finalize() else {
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

// MARK: - CGImageDestination

private extension CGImageDestination {
    func addImage(_ image: CGImage, properties: [CFString: Any]) {
        CGImageDestinationAddImage(self, image, properties as CFDictionary)
    }

    func addImage(
        from source: CGImageSource,
        at index: Int,
        properties: [CFString: Any]
    ) {
        CGImageDestinationAddImageFromSource(
            self,
            source,
            index,
            properties as CFDictionary
        )
    }

    func copyImageSource(_ source: CGImageSource, options: [CFString: Any]) -> Bool {
        CGImageDestinationCopyImageSource(
            self,
            source,
            options as CFDictionary,
            nil
        )
    }

    func finalize() -> Bool {
        CGImageDestinationFinalize(self)
    }
}

// MARK: - CGImageSource

private extension CGImageSource {
    var frameCount: Int {
        CGImageSourceGetCount(self)
    }

    var type: UTType? {
        (CGImageSourceGetType(self) as String?).flatMap(UTType.init)
    }

    func properties(at index: Int) -> [CFString: Any]? {
        CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [CFString: Any]
    }

    func metadata(at index: Int) -> CGImageMetadata? {
        CGImageSourceCopyMetadataAtIndex(self, index, nil)
    }

    func image(at index: Int, options: [CFString: Any]? = nil) -> CGImage? {
        CGImageSourceCreateImageAtIndex(
            self,
            index,
            options.map { $0 as CFDictionary }
        )
    }

    func thumbnail(at index: Int, options: [CFString: Any]) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(
            self,
            index,
            options as CFDictionary
        )
    }
}

// MARK: - CFString Dictionary

extension Dictionary where Key == CFString, Value == Any {
    fileprivate func intValue(for key: CFString) -> Int? {
        switch self[key] {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }

    fileprivate func boolValue(for key: CFString) -> Bool? {
        switch self[key] {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        default:
            return nil
        }
    }
}
