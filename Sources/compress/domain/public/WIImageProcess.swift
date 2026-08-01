//
//  WIImageProcess.swift
//  WICompressDomain
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

/// Pixel sizing applied after an optional crop.
public enum WIImageSizing: Sendable {
    /// Keep the cropped image's pixel size.
    case original
    /// Resolve the final pixel size with a caller-selected implementation.
    case resize(using: any WIImageResizing)
}

/// An immutable description of one deterministic image-processing operation.
public struct WIImageProcess: Sendable {
    public let sizing: WIImageSizing
    public let crop: WIImageCrop?
    public let quality: Double?
    public let output: WIImageOutput

    public init(
        sizing: WIImageSizing = .resize(using: WIImageResize.luban),
        crop: WIImageCrop? = nil,
        quality: Double? = 0.6,
        output: WIImageOutput = WIImageOutput()
    ) {
        self.sizing = sizing
        self.crop = crop
        self.quality = quality?.clamped(to: 0...1, fallback: 0.6)
        self.output = output
    }

    public static let `default` = WIImageProcess()
}
