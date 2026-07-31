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

extension WIImageIO {
    /// Stable source facts produced by ImageIO inspection.
    public struct Descriptor: Sendable, Equatable {
        public let type: UTType?
        public let byteCount: Int
        public let pixelSize: PixelSize
        public let orientation: Orientation
        public let frameCount: Int
        public let hasAlpha: Bool?
        public let metadata: MetadataOptions
        public let hasUnmodeledMetadata: Bool
        public let hasGainMap: Bool

        public var format: Format {
            .detected(from: type)
        }

        public var orientedPixelSize: PixelSize {
            orientation.swapsDimensions
                ? PixelSize(
                    validWidth: pixelSize.height,
                    height: pixelSize.width
                )
                : pixelSize
        }
    }
}
