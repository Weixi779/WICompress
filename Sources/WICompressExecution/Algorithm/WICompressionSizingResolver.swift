//
//  WICompressionSizingResolver.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

struct WIResolvedCompressionSizing: Sendable, Equatable {
    let sourceRect: Rect
    let basePixelSize: WIPixelSize
    let sourcePixelSize: WIPixelSize

    var hasCrop: Bool {
        sourceRect != Rect(
            x: 0,
            y: 0,
            width: Double(sourcePixelSize.width),
            height: Double(sourcePixelSize.height)
        )
    }
}

enum WICompressionSizingResolver {
    static func resolve(
        _ sizing: WICompressionSizing,
        sourcePixelSize: WIPixelSize
    ) throws(WICompressError) -> WIResolvedCompressionSizing {
        let crop = sizing.aspectRatio.map {
            WIImageCrop(aspectRatio: $0, anchor: sizing.anchor)
        }
        let cropGeometry: WIResolvedCropGeometry
        do {
            cropGeometry = try WIImageCropGeometry.resolve(
                crop,
                sourcePixelSize: sourcePixelSize
            )
        } catch WICompressError.invalidCrop {
            throw .invalidTarget
        }

        let basePixelSize: WIPixelSize
        if let maximumPixelSize = sizing.maximumPixelSize {
            basePixelSize = WICompressionSizeEstimation.scaledPixelSize(
                source: cropGeometry.pixelSize,
                maxLongSide: maximumPixelSize
            )
        } else {
            basePixelSize = cropGeometry.pixelSize
        }

        return WIResolvedCompressionSizing(
            sourceRect: cropGeometry.sourceRect,
            basePixelSize: basePixelSize,
            sourcePixelSize: sourcePixelSize
        )
    }
}
