//
//  WIImageMetadata.swift
//  WIImageDomain
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Metadata handling applied to encoded output.
public enum WIImageMetadata: Sendable, Equatable {
    /// Strip non-display metadata such as Exif and GPS.
    case strip
    /// Preserve source metadata where ImageIO supports it.
    case preserve
}
