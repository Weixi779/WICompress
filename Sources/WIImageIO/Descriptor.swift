//
//  Descriptor.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import UniformTypeIdentifiers
import WIImageDomain

package struct Descriptor: Sendable, Equatable {
    package let type: UTType?
    package let byteCount: Int
    package let pixelSize: WIPixelSize
    package let orientation: Orientation
    package let frameCount: Int
    package let hasAlpha: Bool?
    package let metadata: WIImageMetadataOptions
    package let hasUnmodeledMetadata: Bool
    package let hasGainMap: Bool

    package var format: WIImageFormat {
        .detected(from: type)
    }

    package var orientedPixelSize: WIPixelSize {
        orientation.swapsDimensions
            ? WIPixelSize(width: pixelSize.height, height: pixelSize.width)
            : pixelSize
    }
}
