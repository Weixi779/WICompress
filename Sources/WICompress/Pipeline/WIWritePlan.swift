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
    var renderGeometry: WIRenderGeometry?
    var metadataPolicy: WIMetadataPolicy
    var quality: Double?
    var jpegBackground: WIJPEGBackground?
    var outputColorSpace: WIResolvedOutputColorSpace
}

enum WIWritePath: Sendable, Equatable {
    case returnOriginal
    case copyFromSource
    case redrawBitmap
    case redrawCanvas
}

struct WIRenderGeometry: Sendable, Equatable {
    var canvasSize: WIPixelSize
    var destinationRect: WIRect
    var background: WIColor?
}

struct WIResolvedOutputColorSpace: Sendable, Equatable {
    var target: WIColorSpace?

    var requiresConversion: Bool {
        target != nil
    }
}
