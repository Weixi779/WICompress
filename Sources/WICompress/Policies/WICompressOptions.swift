//
//  WICompressOptions.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Policies that control resize, format, metadata, quality, and color-space handling.
public struct WICompressOptions: Sendable, Equatable {
    /// Resize policy applied before encoding.
    public var resize: WIResizePolicy
    /// Destination container policy.
    public var format: WIFormatPolicy
    /// Metadata handling policy.
    public var metadata: WIMetadataPolicy
    /// Lossy quality policy.
    public var quality: WIQualityPolicy
    /// Output color-space policy.
    public var colorSpace: WIOutputColorSpace

    /// Creates compression options with upload-compression defaults unless overridden.
    public init(
        resize: WIResizePolicy = .luban,
        format: WIFormatPolicy = .preserve,
        metadata: WIMetadataPolicy = .strip,
        quality: WIQualityPolicy = .compression(0.6),
        colorSpace: WIOutputColorSpace = .preserve
    ) {
        self.resize = resize
        self.format = format
        self.metadata = metadata
        self.quality = quality
        self.colorSpace = colorSpace
    }

    /// Default upload-compression options.
    public static let `default` = WICompressOptions()
}
