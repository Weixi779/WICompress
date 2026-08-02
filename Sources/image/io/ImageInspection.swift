//
//  ImageInspection.swift
//  WIImageIO
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import WIImageDomain

/// Stable source facts produced by ImageIO inspection.
public struct ImageDescriptor: Sendable, Equatable {
    public let type: UTType?
    public let byteCount: Int
    public let pixelSize: WIPixelSize
    public let orientation: WIImageOrientation
    public let frameCount: Int
    public let hasAlpha: Bool?
    public let metadata: ImageMetadataOptions
    package let hasUnmodeledMetadata: Bool
    public let hasGainMap: Bool

    public var format: ImageFormat {
        .detected(from: type)
    }

    public var orientedPixelSize: WIPixelSize {
        pixelSize.oriented(by: orientation)
    }
}

extension ImageReader {
    /// Opens encoded image data for inspection and pixel operations.
    public convenience init(_ data: Data) throws(ImageIOError) {
        let source = try Self.imageSource(data)
        self.init(
            source: source,
            descriptor: try Self.descriptor(source, byteCount: data.count)
        )
    }

    /// Opens an encoded image file without loading its complete bytes.
    public convenience init(contentsOf url: URL) throws(ImageIOError) {
        let (source, byteCount) = try Self.imageSource(contentsOf: url)
        self.init(
            source: source,
            descriptor: try Self.descriptor(source, byteCount: byteCount)
        )
    }

    /// Inspects encoded image data without decoding its pixels.
    public static func inspect(_ data: Data) throws(ImageIOError) -> ImageDescriptor {
        try ImageReader(data).descriptor
    }

    /// Inspects an encoded image file without loading its complete bytes.
    public static func inspect(contentsOf url: URL) throws(ImageIOError) -> ImageDescriptor {
        try ImageReader(contentsOf: url).descriptor
    }

    private static func imageSource(_ data: Data) throws(ImageIOError) -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw .invalidImageData
        }
        return source
    }

    private static func imageSource(
        contentsOf url: URL
    ) throws(ImageIOError) -> (source: CGImageSource, byteCount: Int) {
        let byteCount = try fileByteCount(for: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw .invalidImageData
        }
        return (source, byteCount)
    }

    private static func descriptor(
        _ source: CGImageSource,
        byteCount: Int
    ) throws(ImageIOError) -> ImageDescriptor {
        let frameCount = source.inspectionFrameCount
        guard frameCount > 0 else {
            throw .invalidImageData
        }

        guard let properties = source.inspectionProperties(at: 0) else {
            throw .imageInfoUnavailable
        }

        guard
            let pixelWidth = properties.intValue(for: kCGImagePropertyPixelWidth),
            let pixelHeight = properties.intValue(for: kCGImagePropertyPixelHeight)
        else {
            throw .imageInfoUnavailable
        }

        let pixelSize = try pixelSize(width: pixelWidth, height: pixelHeight)
        let orientationValue = properties.intValue(for: kCGImagePropertyOrientation)
            ?? WIImageOrientation.up.rawValue
        guard let orientation = WIImageOrientation(rawValue: orientationValue) else {
            throw .imageInfoUnavailable
        }

        return ImageDescriptor(
            type: source.inspectionType,
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
    ) throws(ImageIOError) -> WIPixelSize {
        guard width > 0, height > 0 else {
            throw .imageInfoUnavailable
        }

        let (_, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw .imageInfoUnavailable
        }

        return WIPixelSize(validWidth: width, height: height)
    }

    private static func fileByteCount(for url: URL) throws(ImageIOError) -> Int {
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
            throw .fileReadFailed(url)
        }

        return fileSize.intValue
    }
}

private extension CGImageSource {
    var inspectionFrameCount: Int {
        CGImageSourceGetCount(self)
    }

    var inspectionType: UTType? {
        (CGImageSourceGetType(self) as String?).flatMap(UTType.init)
    }

    func inspectionProperties(at index: Int) -> [CFString: Any]? {
        CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [CFString: Any]
    }
}

private extension Dictionary where Key == CFString, Value == Any {
    func intValue(for key: CFString) -> Int? {
        switch self[key] {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }

    func boolValue(for key: CFString) -> Bool? {
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
