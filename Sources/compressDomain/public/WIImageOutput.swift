//
//  WIImageOutput.swift
//  WICompressDomain
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

/// Color-space handling applied to encoded output.
public enum WIImageColorSpace: Sendable, Equatable {
    /// Preserve the source image's normal display semantics.
    case preserve
    /// Convert rendered pixels to a concrete color space.
    case convert(to: WIColorSpace)
}

/// Immutable representation, metadata, and color-space requirements.
public struct WIImageOutput: Sendable, Equatable {
    public let representation: WIImageRepresentation
    public let metadata: WIImageMetadataOptions
    public let colorSpace: WIImageColorSpace

    public init(
        representation: WIImageRepresentation = .preserve,
        metadata: WIImageMetadataOptions = .strip,
        colorSpace: WIImageColorSpace = .preserve
    ) {
        self.representation = representation
        self.metadata = metadata
        self.colorSpace = colorSpace
    }
}
