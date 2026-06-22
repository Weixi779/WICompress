//
//  WICompressOptions.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Policies that control resize, format, metadata, and quality handling.
public struct WICompressOptions: Sendable, Equatable {
    /// Resize policy applied before encoding.
    public var resize: WIResizePolicy
    /// Destination container policy.
    public var format: WIFormatPolicy
    /// Metadata handling policy.
    public var metadata: WIMetadataPolicy
    /// Lossy quality policy.
    public var quality: WIQualityPolicy

    /// Creates compression options with upload-compression defaults unless overridden.
    public init(
        resize: WIResizePolicy = .luban,
        format: WIFormatPolicy = .preserve,
        metadata: WIMetadataPolicy = .strip,
        quality: WIQualityPolicy = .compression(0.6)
    ) {
        self.resize = resize
        self.format = format
        self.metadata = metadata
        self.quality = quality
    }

    /// Default upload-compression options.
    public static let `default` = WICompressOptions()
}
