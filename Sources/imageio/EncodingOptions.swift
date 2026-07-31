//
//  EncodingOptions.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import WIImageDomain

extension WIImageIO {
    /// Source-copy encoding behavior that avoids pixel decoding when supported.
    public struct CopyOptions: Hashable, Sendable {
        public var maximumPixelSize: Int?
        public var compressionQuality: Double?
        public var metadata: MetadataOptions

        public init(
            maximumPixelSize: Int? = nil,
            compressionQuality: Double? = nil,
            metadata: MetadataOptions = .preserve
        ) {
            self.maximumPixelSize = maximumPixelSize
            self.compressionQuality = compressionQuality
            self.metadata = metadata
        }
    }

    /// Pixel encoding quality and metadata behavior.
    public struct EncodeOptions: Hashable, Sendable {
        public var compressionQuality: Double?
        public var metadata: MetadataOptions

        public init(
            compressionQuality: Double? = nil,
            metadata: MetadataOptions = .strip
        ) {
            self.compressionQuality = compressionQuality
            self.metadata = metadata
        }
    }
}
