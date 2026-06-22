//
//  WIMetadataPolicy.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Metadata handling policy.
public enum WIMetadataPolicy: Sendable, Equatable {
    /// Strip non-display metadata such as Exif and GPS.
    case strip
    /// Preserve source metadata where ImageIO supports it.
    case preserve
}
