//
//  WIWritePlan.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

struct WIWritePlan: Sendable, Equatable {
    var path: WIWritePath
    var destinationFormat: WIImageFormat
    var destinationTypeIdentifier: String
    var maxPixelSize: Int?
    var targetPixelSize: WIPixelSize?
    var metadataPolicy: WIMetadataPolicy
    var quality: Double?
    var jpegBackground: WIJPEGBackground?
}

struct WIPixelSize: Sendable, Equatable {
    var width: Int
    var height: Int
}

enum WIWritePath: Sendable, Equatable {
    case returnOriginal
    case copyFromSource
    case redrawBitmap
}
