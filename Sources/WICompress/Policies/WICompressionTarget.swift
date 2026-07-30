//
//  WICompressionTarget.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Candidate ranking preference for target-based compression.
public enum WICompressionPreference: Sendable, Equatable {
    /// Balance output dimensions and fidelity.
    case balanced
    /// Prefer larger dimensions when candidates are close.
    case preserveResolution
    /// Prefer higher visual fidelity when candidates are close.
    case preserveFidelity
}

/// Result constraints for target-based compression.
public struct WICompressionTarget: Sendable, Equatable {
    /// Maximum allowed encoded byte count.
    public var maxBytes: Int
    /// Output geometry intent.
    public var geometry: WICompressionGeometry
    /// Immutable representation, metadata, and color-space requirements.
    public var output: WIImageOutput
    /// Candidate ranking preference.
    public var preference: WICompressionPreference

    /// Creates a target compression request.
    public init(
        maxBytes: Int,
        geometry: WICompressionGeometry = .original,
        output: WIImageOutput = WIImageOutput(
            representation: .pngIfAlphaOtherwiseJPEG,
            metadata: .strip,
            colorSpace: .convert(to: .sRGB)
        ),
        preference: WICompressionPreference = .balanced
    ) {
        self.maxBytes = maxBytes
        self.geometry = geometry
        self.output = output
        self.preference = preference
    }
}
