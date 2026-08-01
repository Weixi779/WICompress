//
//  ImageTranscoding.swift
//  WIImageIO
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import WIImageDomain

/// Source transcoding behavior that avoids pixel decoding when supported.
public struct ImageTranscodeOptions: Hashable, Sendable {
    public let maximumPixelSize: Int?
    public let compressionQuality: Double?
    public let metadata: ImageMetadataOptions

    public init(
        maximumPixelSize: Int? = nil,
        compressionQuality: Double? = nil,
        metadata: ImageMetadataOptions = .preserve
    ) {
        self.maximumPixelSize = maximumPixelSize.map { max(1, $0) }
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
    /// Transcodes the encoded source without decoding pixels when the options allow it.
    public func transcode(
        as type: UTType,
        options: ImageTranscodeOptions = .init()
    ) throws(ImageIOError) -> Data {
        try validateTranscodableSource()

        guard let method = transcodeMethod(as: type, options: options) else {
            throw .metadataTranscodeUnsupported(type)
        }

        switch method {
        case .addImageFromSource:
            return try addImageFromSource(as: type, options: options)
        case .copyImageSourceExcludingGPS:
            return try copyImageSourceExcludingGPS(as: type)
        }
    }

    package func canTranscode(
        as type: UTType,
        options: ImageTranscodeOptions = .init()
    ) -> Bool {
        guard descriptor.frameCount == 1 else {
            return false
        }
        guard ImageReader.canEncode(type) else {
            return false
        }

        return transcodeMethod(as: type, options: options) != nil
    }

    private enum TranscodeMethod {
        case addImageFromSource
        case copyImageSourceExcludingGPS
    }

    private func transcodeMethod(
        as type: UTType,
        options: ImageTranscodeOptions
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

    private func addImageFromSource(
        as type: UTType,
        options: ImageTranscodeOptions
    ) throws(ImageIOError) -> Data {
        var properties: [CFString: Any] = [:]
        if let maximumPixelSize = options.maximumPixelSize {
            properties[kCGImageDestinationImageMaxPixelSize] = maximumPixelSize
        }
        if let compressionQuality = options.compressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        }

        return try transcodedData(as: type, properties: properties)
    }

    private func copyImageSourceExcludingGPS(
        as type: UTType
    ) throws(ImageIOError) -> Data {
        guard let metadata = source.transcodeMetadata(at: 0) else {
            throw .imageInfoUnavailable
        }

        let outputData = NSMutableData()
        let destination = try Self.destination(as: type, writingTo: outputData)

        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: true,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        guard destination.copyTranscodedSource(source, options: options) else {
            throw .imageEncodeFailed(type)
        }
        return outputData as Data
    }

    private func validateTranscodableSource() throws(ImageIOError) {
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: frameCount)
        }
    }

    private func transcodedData(
        as type: UTType,
        properties: [CFString: Any]
    ) throws(ImageIOError) -> Data {
        let outputData = NSMutableData()
        let destination = try Self.destination(as: type, writingTo: outputData)
        destination.addTranscodedImage(
            from: source,
            at: 0,
            properties: properties
        )

        guard destination.finalizeTranscode() else {
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

private extension CGImageSource {
    func transcodeMetadata(at index: Int) -> CGImageMetadata? {
        CGImageSourceCopyMetadataAtIndex(self, index, nil)
    }
}

private extension CGImageDestination {
    func addTranscodedImage(
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

    func copyTranscodedSource(
        _ source: CGImageSource,
        options: [CFString: Any]
    ) -> Bool {
        CGImageDestinationCopyImageSource(
            self,
            source,
            options as CFDictionary,
            nil
        )
    }

    func finalizeTranscode() -> Bool {
        CGImageDestinationFinalize(self)
    }
}
