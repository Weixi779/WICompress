//
//  ImageDecoding.swift
//  WIImageIO
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WIImageDomain

/// Pixel decoding behavior for a full image frame.
public struct ImageDecodeOptions: Hashable, Sendable {
    public let cacheImmediately: Bool

    public init(cacheImmediately: Bool = true) {
        self.cacheImmediately = cacheImmediately
    }
}

/// ImageIO thumbnail decoding behavior.
public struct ImageThumbnailOptions: Hashable, Sendable {
    public let maximumPixelSize: Int?
    public let appliesOrientationTransform: Bool
    public let cacheImmediately: Bool

    public init(
        maximumPixelSize: Int? = nil,
        appliesOrientationTransform: Bool = true,
        cacheImmediately: Bool = true
    ) {
        self.maximumPixelSize = maximumPixelSize.map { max(1, $0) }
        self.appliesOrientationTransform = appliesOrientationTransform
        self.cacheImmediately = cacheImmediately
    }
}

extension ImageReader {
    /// Whether the current ImageIO runtime can decode the supplied type.
    public static func canDecode(_ type: UTType) -> Bool {
        readableTypes.contains(type)
    }

    /// Reads the source color space when it can be represented by this module.
    public func colorSpace() throws(ImageIOError) -> WIColorSpace? {
        guard let image = source.decodedImage(at: 0) else {
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

    /// Decodes the source frame without applying its display orientation.
    public func image(
        options: ImageDecodeOptions = .init()
    ) throws(ImageIOError) -> ImageFrame {
        try validateDecodableSource()

        let properties: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: options.cacheImmediately
        ]
        guard let image = source.decodedImage(at: 0, options: properties) else {
            throw .imageDecodeFailed
        }

        return ImageFrame(
            image: image,
            orientation: descriptor.orientation,
            metadataProvenance: Self.metadataProvenance(source)
        )
    }

    /// Decodes a thumbnail and optionally applies its display orientation.
    public func thumbnail(
        options: ImageThumbnailOptions = .init()
    ) throws(ImageIOError) -> ImageFrame {
        try validateDecodableSource()

        var properties: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: options.appliesOrientationTransform,
            kCGImageSourceShouldCacheImmediately: options.cacheImmediately,
        ]
        if let maximumPixelSize = options.maximumPixelSize {
            properties[kCGImageSourceThumbnailMaxPixelSize] = maximumPixelSize
        }

        guard let image = source.decodedThumbnail(at: 0, options: properties) else {
            throw .imageDecodeFailed
        }

        return ImageFrame(
            image: image,
            orientation: options.appliesOrientationTransform
                ? .up
                : descriptor.orientation,
            metadataProvenance: Self.metadataProvenance(source)
        )
    }

    private func validateDecodableSource() throws(ImageIOError) {
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: frameCount)
        }
    }

    private static let readableTypes: Set<UTType> = {
        guard let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] else {
            return []
        }
        return Set(identifiers.compactMap(UTType.init))
    }()
}

private extension CGImageSource {
    func decodedImage(
        at index: Int,
        options: [CFString: Any]? = nil
    ) -> CGImage? {
        CGImageSourceCreateImageAtIndex(
            self,
            index,
            options.map { $0 as CFDictionary }
        )
    }

    func decodedThumbnail(
        at index: Int,
        options: [CFString: Any]
    ) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(
            self,
            index,
            options as CFDictionary
        )
    }
}
