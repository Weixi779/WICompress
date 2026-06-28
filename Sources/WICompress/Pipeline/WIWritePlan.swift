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

/// Integer pixel size used internally by rendering and encoding plans.
struct WIPixelSize: Sendable, Equatable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init(_ size: WISize) {
        self.init(
            width: max(Int(size.width.rounded(.toNearestOrAwayFromZero)), 1),
            height: max(Int(size.height.rounded(.toNearestOrAwayFromZero)), 1)
        )
    }
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

struct WIRect: Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct WIResolvedOutputColorSpace: Sendable, Equatable {
    var target: WIColorSpace?

    var requiresConversion: Bool {
        target != nil
    }
}
