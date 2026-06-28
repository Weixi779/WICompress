//
//  WICompressionTarget.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Output contract used by target-based compression.
public struct WICompressionOutput: Sendable, Equatable {
    /// Destination container policy.
    public var format: WIFormatPolicy
    /// Metadata handling policy.
    public var metadata: WIMetadataPolicy
    /// Output color-space policy.
    public var colorSpace: WIOutputColorSpace

    /// Creates an output contract.
    public init(
        format: WIFormatPolicy = .pngIfAlphaOtherwiseJPEG,
        metadata: WIMetadataPolicy = .strip,
        colorSpace: WIOutputColorSpace = .preserve
    ) {
        self.format = format
        self.metadata = metadata
        self.colorSpace = colorSpace
    }

    /// Upload-oriented output defaults.
    public static let upload = WICompressionOutput()

    /// Preserve source format, metadata, and color-space semantics.
    public static let preserve = WICompressionOutput(
        format: .preserve,
        metadata: .preserve,
        colorSpace: .preserve
    )
}

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
    /// Output format, metadata, and color-space contract.
    public var output: WICompressionOutput
    /// Candidate ranking preference.
    public var preference: WICompressionPreference

    /// Creates a target compression request.
    public init(
        maxBytes: Int,
        geometry: WICompressionGeometry = .original,
        output: WICompressionOutput = .upload,
        preference: WICompressionPreference = .balanced
    ) {
        self.maxBytes = maxBytes
        self.geometry = geometry
        self.output = output
        self.preference = preference
    }
}
