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
    var metadataPolicy: WIMetadataPolicy
    var quality: Double?
    var jpegBackground: WIJPEGBackground?
}

enum WIWritePath: Sendable, Equatable {
    case returnOriginal
    case copyFromSource
    case redrawBitmap
}
