//
//  WIImageInfo.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageCore

struct WISourceColorSpaceInfo: Sendable, Equatable {
    let colorSpace: ColorSpace?
}

struct WIImageInfo: Sendable, Equatable {
    let sourceFormat: ImageFormat
    let typeIdentifier: String?
    let pixelSize: PixelSize
    let orientation: Orientation
    let frameCount: Int
    let isSourceFormatWritable: Bool
    let hasMetadata: Bool
    let hasGPS: Bool
    let hasGainMap: Bool
    let hasAlpha: Bool?

    var displayWidth: Int {
        orientation.swapsDimensions ? pixelSize.height : pixelSize.width
    }

    var displayHeight: Int {
        orientation.swapsDimensions ? pixelSize.width : pixelSize.height
    }

    var displaySize: WISize {
        WISize(width: Double(displayWidth), height: Double(displayHeight))
    }

    var displayDimensions: (width: Int, height: Int) {
        (displayWidth, displayHeight)
    }
}
