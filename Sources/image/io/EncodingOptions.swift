//
//  EncodingOptions.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import WIImageDomain

extension WIImageIO {
    /// Source transcoding behavior that avoids pixel decoding when supported.
    public struct TranscodeOptions: Hashable, Sendable {
        public let maximumPixelSize: Int?
        public let compressionQuality: Double?
        public let metadata: WIImageMetadataOptions

        public init(
            maximumPixelSize: Int? = nil,
            compressionQuality: Double? = nil,
            metadata: WIImageMetadataOptions = .preserve
        ) {
            self.maximumPixelSize = maximumPixelSize.map { max(1, $0) }
            self.compressionQuality = normalizedCompressionQuality(
                compressionQuality
            )
            self.metadata = metadata
        }
    }

    /// Pixel encoding quality and metadata behavior.
    public struct EncodeOptions: Hashable, Sendable {
        public let compressionQuality: Double?
        public let metadata: WIImageMetadataOptions

        public init(
            compressionQuality: Double? = nil,
            metadata: WIImageMetadataOptions = .strip
        ) {
            self.compressionQuality = normalizedCompressionQuality(
                compressionQuality
            )
            self.metadata = metadata
        }
    }
}

private func normalizedCompressionQuality(_ quality: Double?) -> Double? {
    guard let quality, quality.isFinite else {
        return nil
    }
    return min(max(quality, 0), 1)
}
