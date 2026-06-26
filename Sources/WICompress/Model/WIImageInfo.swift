//
//  WIImageInfo.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

struct WIImageInfo: Sendable, Equatable {
    let sourceFormat: WIImageFormat
    let typeIdentifier: String?
    let pixelWidth: Int
    let pixelHeight: Int
    let orientation: Int
    let frameCount: Int
    let isSourceFormatWritable: Bool
    let hasMetadata: Bool
    let hasGPS: Bool
    let hasGainMap: Bool
    let hasAlpha: Bool?

    var displayWidth: Int {
        swapsDisplayDimensions ? pixelHeight : pixelWidth
    }

    var displayHeight: Int {
        swapsDisplayDimensions ? pixelWidth : pixelHeight
    }

    var displayLongSide: Int {
        max(displayWidth, displayHeight)
    }

    private var swapsDisplayDimensions: Bool {
        switch orientation {
        case 5, 6, 7, 8:
            return true
        default:
            return false
        }
    }
}
