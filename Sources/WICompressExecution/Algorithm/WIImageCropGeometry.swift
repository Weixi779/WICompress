//
//  WIImageCropGeometry.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

struct WIResolvedCropGeometry: Sendable, Equatable {
    let sourceRect: Rect
    let pixelSize: WIPixelSize
}

enum WIImageCropGeometry {
    static func resolve(
        _ crop: WIImageCrop?,
        sourcePixelSize: WIPixelSize
    ) throws(WICompressError) -> WIResolvedCropGeometry {
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0 else {
            throw .imageInfoUnavailable
        }

        guard let crop else {
            return WIResolvedCropGeometry(
                sourceRect: Rect(
                    x: 0,
                    y: 0,
                    width: Double(sourcePixelSize.width),
                    height: Double(sourcePixelSize.height)
                ),
                pixelSize: sourcePixelSize
            )
        }

        let ratioWidth = crop.aspectRatio.width
        let ratioHeight = crop.aspectRatio.height
        let anchor = crop.anchor
        guard
            ratioWidth.isFinite,
            ratioHeight.isFinite,
            ratioWidth > 0,
            ratioHeight > 0,
            anchor.x.isFinite,
            anchor.y.isFinite,
            (0...1).contains(anchor.x),
            (0...1).contains(anchor.y)
        else {
            throw .invalidCrop
        }

        let targetRatio = ratioWidth / ratioHeight
        guard targetRatio.isFinite, targetRatio > 0 else {
            throw .invalidCrop
        }

        let sourceWidth = sourcePixelSize.width
        let sourceHeight = sourcePixelSize.height
        let sourceRatio = Double(sourceWidth) / Double(sourceHeight)

        let cropWidth: Int
        let cropHeight: Int
        if sourceRatio > targetRatio {
            cropHeight = sourceHeight
            guard let resolvedWidth = Int(
                exactly: (Double(sourceHeight) * targetRatio).rounded(.down)
            ) else {
                throw .invalidCrop
            }
            cropWidth = max(min(resolvedWidth, sourceWidth), 1)
        } else if sourceRatio < targetRatio {
            cropWidth = sourceWidth
            guard let resolvedHeight = Int(
                exactly: (Double(sourceWidth) / targetRatio).rounded(.down)
            ) else {
                throw .invalidCrop
            }
            cropHeight = max(min(resolvedHeight, sourceHeight), 1)
        } else {
            cropWidth = sourceWidth
            cropHeight = sourceHeight
        }

        let availableX = sourceWidth - cropWidth
        let availableY = sourceHeight - cropHeight
        guard
            let anchoredX = Int(
                exactly: (Double(availableX) * anchor.x)
                    .rounded(.toNearestOrAwayFromZero)
            ),
            let anchoredY = Int(
                exactly: (Double(availableY) * anchor.y)
                    .rounded(.toNearestOrAwayFromZero)
            )
        else {
            throw .invalidCrop
        }

        let originX = min(max(anchoredX, 0), availableX)
        let originY = min(max(anchoredY, 0), availableY)
        return WIResolvedCropGeometry(
            sourceRect: Rect(
                x: Double(originX),
                y: Double(originY),
                width: Double(cropWidth),
                height: Double(cropHeight)
            ),
            pixelSize: WIPixelSize(width: cropWidth, height: cropHeight)
        )
    }
}
