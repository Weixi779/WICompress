//
//  WIResizePolicy.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Resize strategy applied before encoding.
public enum WIResizePolicy: Sendable, Equatable {
    /// Keep the source display dimensions.
    case none
    /// Apply the Luban resize ratio.
    case luban
    /// Cap the longest display side without upscaling smaller images.
    case maxPixel(Int)
}
