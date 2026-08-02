//
//  WICompressionSizing+Geometry.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WICompressDomain
import WIImageDomain

struct TargetGeometry: Sendable, Equatable {
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

extension WICompressionSizing {
    func geometry(
        for sourcePixelSize: WIPixelSize
    ) throws(WICompressError) -> TargetGeometry {
        let crop = aspectRatio.map {
            WIImageCrop(aspectRatio: $0, anchor: anchor)
        }
        let cropGeometry: CropGeometry
        do {
            cropGeometry = try ImageCropGeometry.resolve(
                crop,
                sourcePixelSize: sourcePixelSize
            )
        } catch WICompressError.invalidCrop {
            throw .invalidTarget
        }

        let basePixelSize: WIPixelSize
        if let maximumPixelSize {
            basePixelSize = TargetSizeEstimation.scaledPixelSize(
                source: cropGeometry.pixelSize,
                maxLongSide: maximumPixelSize
            )
        } else {
            basePixelSize = cropGeometry.pixelSize
        }

        return TargetGeometry(
            sourceRect: cropGeometry.sourceRect,
            basePixelSize: basePixelSize,
            sourcePixelSize: sourcePixelSize
        )
    }
}
