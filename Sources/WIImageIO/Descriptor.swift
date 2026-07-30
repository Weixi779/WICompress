//
//  Descriptor.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

package struct Descriptor: Sendable, Equatable {
    package let format: WIImageFormat
    package let typeIdentifier: String?
    package let byteCount: Int
    package let pixelSize: WIPixelSize
    package let orientedPixelSize: WIPixelSize
    package let orientation: Orientation
    package let frameCount: Int
    package let hasAlpha: Bool?
    package let hasMetadata: Bool
    package let hasGPS: Bool
    package let hasGainMap: Bool
    package let isSourceFormatDecodable: Bool
    package let isSourceFormatWritable: Bool
}
