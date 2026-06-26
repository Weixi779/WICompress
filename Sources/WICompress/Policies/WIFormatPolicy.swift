//
//  WIFormatPolicy.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Background handling used when encoding transparent sources as JPEG.
public enum WIJPEGBackground: Sendable, Equatable {
    /// Reject transparent sources instead of silently flattening them.
    case disallow
    /// Flatten transparent pixels over white.
    case white
    /// Flatten transparent pixels over black.
    case black
}

/// Destination container policy.
public enum WIFormatPolicy: Sendable, Equatable {
    /// Preserve the source image container format.
    case preserve
    /// Encode the output as JPEG.
    case jpeg(background: WIJPEGBackground = .disallow)
    /// Encode alpha-channel sources as PNG and opaque sources as JPEG.
    case pngIfAlphaOtherwiseJPEG
    /// Encode the output as PNG.
    case png
    /// Encode the output as HEIC.
    case heic
}
