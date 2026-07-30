//
//  Descriptor.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageCore

package struct Descriptor: Sendable, Equatable {
    package let format: ImageFormat
    package let typeIdentifier: String?
    package let byteCount: Int
    package let pixelSize: PixelSize
    package let orientedPixelSize: PixelSize
    package let orientation: Orientation
    package let frameCount: Int
    package let hasAlpha: Bool?
    package let hasMetadata: Bool
    package let hasGPS: Bool
    package let hasGainMap: Bool
    package let isSourceFormatDecodable: Bool
    package let isSourceFormatWritable: Bool
}
