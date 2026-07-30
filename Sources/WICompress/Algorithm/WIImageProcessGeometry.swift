//
//  WIImageProcessGeometry.swift
//  WICompress
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

struct WIResolvedProcessGeometry: Sendable, Equatable {
    let sourceRect: WIRect
    let croppedPixelSize: WIPixelSize
    let targetPixelSize: WIPixelSize
    let sourcePixelSize: WIPixelSize

    var hasCrop: Bool {
        sourceRect != WIRect(
            x: 0,
            y: 0,
            width: Double(sourcePixelSize.width),
            height: Double(sourcePixelSize.height)
        )
    }

    var changesPixelSize: Bool {
        targetPixelSize != croppedPixelSize
    }
}

enum WIImageProcessGeometry {
    static func resolve(
        process: WIImageProcess,
        sourcePixelSize: WIPixelSize
    ) throws(WICompressError) -> WIResolvedProcessGeometry {
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0 else {
            throw .imageInfoUnavailable
        }

        let cropGeometry = try cropGeometry(
            process.crop,
            sourcePixelSize: sourcePixelSize
        )
        let targetPixelSize: WIPixelSize
        switch process.sizing {
        case .original:
            targetPixelSize = cropGeometry.pixelSize
        case .resize(let resizing):
            targetPixelSize = resizing.targetSize(for: cropGeometry.pixelSize)
        }

        try validateExecutablePixelSize(targetPixelSize)

        return WIResolvedProcessGeometry(
            sourceRect: cropGeometry.rect,
            croppedPixelSize: cropGeometry.pixelSize,
            targetPixelSize: targetPixelSize,
            sourcePixelSize: sourcePixelSize
        )
    }

    private static func validateExecutablePixelSize(
        _ size: WIPixelSize
    ) throws(WICompressError) {
        guard size.width > 0, size.height > 0 else {
            throw .invalidResizingResult
        }

        let (minimumRowBytes, rowOverflow) = size.width
            .multipliedReportingOverflow(by: 4)
        guard !rowOverflow else {
            throw .invalidResizingResult
        }

        let (alignmentInput, alignmentOverflow) = minimumRowBytes
            .addingReportingOverflow(63)
        guard !alignmentOverflow else {
            throw .invalidResizingResult
        }

        let alignedRowBytes = (alignmentInput / 64) * 64
        let (_, totalOverflow) = alignedRowBytes
            .multipliedReportingOverflow(by: size.height)
        guard !totalOverflow else {
            throw .invalidResizingResult
        }
    }

    private static func cropGeometry(
        _ crop: WIImageCrop?,
        sourcePixelSize: WIPixelSize
    ) throws(WICompressError) -> (
        rect: WIRect,
        pixelSize: WIPixelSize
    ) {
        guard let crop else {
            return (
                WIRect(
                    x: 0,
                    y: 0,
                    width: Double(sourcePixelSize.width),
                    height: Double(sourcePixelSize.height)
                ),
                sourcePixelSize
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
        let originX = min(
            max(anchoredX, 0),
            availableX
        )
        let originY = min(
            max(anchoredY, 0),
            availableY
        )

        return (
            WIRect(
                x: Double(originX),
                y: Double(originY),
                width: Double(cropWidth),
                height: Double(cropHeight)
            ),
            WIPixelSize(width: cropWidth, height: cropHeight)
        )
    }
}
