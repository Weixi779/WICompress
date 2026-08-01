//
//  WIResult.swift
//  WICompressDomain
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

/// Encoded result produced by WICompress.
public struct WIResult: Sendable {
    /// Encoded image data.
    public let data: Data
    /// Encoded image format.
    public let format: ImageFormat
    /// Encoded pixel size.
    public let pixelSize: WIPixelSize
    /// Encoded byte count.
    public var byteCount: Int {
        data.count
    }

    package init(
        data: Data,
        format: ImageFormat,
        pixelSize: WIPixelSize
    ) {
        self.data = data
        self.format = format
        self.pixelSize = pixelSize
    }
}
