//
//  WICompressionTarget.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Result constraints for target-based compression.
public struct WICompressionTarget: Sendable, Equatable {
    /// Maximum allowed encoded byte count.
    public let maxBytes: Int
    /// Base pixel constraints resolved before byte search.
    public let sizing: WICompressionSizing
    /// Immutable representation, metadata, and color-space requirements.
    public let output: WIImageOutput

    /// Creates a target compression request.
    public init(
        maxBytes: Int,
        sizing: WICompressionSizing = WICompressionSizing(),
        output: WIImageOutput = WIImageOutput(
            representation: .pngIfAlphaOtherwiseJPEG,
            metadata: .strip,
            colorSpace: .convert(to: .sRGB)
        )
    ) {
        self.maxBytes = maxBytes
        self.sizing = sizing
        self.output = output
    }
}
