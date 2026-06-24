//
//  WICompressionTarget.swift
//  WICompress
//
//  Created by weixi on 2026/6/24.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Final output constraints for target-size compression.
public struct WICompressionTarget: Sendable, Equatable {
    /// Hard upper bound for encoded output bytes.
    public var maxBytes: Int
    /// Optional upper bound for the EXIF-oriented display long side.
    public var maxLongSide: Int?
    /// Destination container policy.
    public var format: WIFormatPolicy
    /// Metadata handling policy.
    public var metadata: WIMetadataPolicy

    /// Creates target compression constraints.
    public init(
        maxBytes: Int,
        maxLongSide: Int? = nil,
        format: WIFormatPolicy = .preserve,
        metadata: WIMetadataPolicy = .strip
    ) {
        self.maxBytes = maxBytes
        self.maxLongSide = maxLongSide
        self.format = format
        self.metadata = metadata
    }
}
