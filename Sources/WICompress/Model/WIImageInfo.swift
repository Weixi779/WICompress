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
}
