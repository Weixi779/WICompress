//
//  WICompressionResult.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Encoded result produced by target-based compression.
public struct WICompressionResult: Sendable {
    /// Encoded image data.
    public let data: Data
    /// Encoded image format.
    public let format: WIImageFormat
    /// Encoded pixel size. Values are integer pixels represented as `WISize`.
    public let pixelSize: WISize
    /// Encoded byte count.
    public let byteCount: Int

    /// Creates a target compression result.
    public init(data: Data, format: WIImageFormat, pixelSize: WISize, byteCount: Int) {
        self.data = data
        self.format = format
        self.pixelSize = pixelSize
        self.byteCount = byteCount
    }
}
