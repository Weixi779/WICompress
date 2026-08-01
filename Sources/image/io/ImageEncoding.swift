//
//  ImageEncoding.swift
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

/// Pixel encoding quality and metadata behavior.
public struct ImageEncodeOptions: Hashable, Sendable {
    public let compressionQuality: Double?
    public let metadata: ImageMetadataOptions

    public init(
        compressionQuality: Double? = nil,
        metadata: ImageMetadataOptions = .strip
    ) {
        self.compressionQuality = Self.normalizedQuality(compressionQuality)
        self.metadata = metadata
    }

    private static func normalizedQuality(_ quality: Double?) -> Double? {
        guard let quality, quality.isFinite else {
            return nil
        }
        return min(max(quality, 0), 1)
    }
}

extension ImageReader {
    /// Whether the current ImageIO runtime can encode the supplied type.
    public static func canEncode(_ type: UTType) -> Bool {
        writableTypes.contains(type)
    }

    private static let writableTypes: Set<UTType> = {
        guard let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] else {
            return []
        }
        return Set(identifiers.compactMap(UTType.init))
    }()
}

extension ImageFrame {
    /// Encodes the frame while retaining selected source metadata when available.
    public func encode(
        as type: UTType,
        options: ImageEncodeOptions = .init()
    ) throws(ImageIOError) -> Data {
        var properties = metadataProvenance?.properties(
            keeping: options.metadata
        ) ?? [:]

        if let compressionQuality = options.compressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        }
        properties[kCGImagePropertyOrientation] = orientation.rawValue

        return try encodedData(as: type, properties: properties)
    }

    private func encodedData(
        as type: UTType,
        properties: [CFString: Any]
    ) throws(ImageIOError) -> Data {
        let outputData = NSMutableData()
        let destination = try Self.destination(as: type, writingTo: outputData)
        destination.addFrame(image, properties: properties)

        guard destination.finalizeFrame() else {
            throw .imageEncodeFailed(type)
        }
        return outputData as Data
    }

    private static func destination(
        as type: UTType,
        writingTo data: NSMutableData
    ) throws(ImageIOError) -> CGImageDestination {
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

private extension CGImageDestination {
    func addFrame(
        _ image: CGImage,
        properties: [CFString: Any]
    ) {
        CGImageDestinationAddImage(
            self,
            image,
            properties as CFDictionary
        )
    }

    func finalizeFrame() -> Bool {
        CGImageDestinationFinalize(self)
    }
}
