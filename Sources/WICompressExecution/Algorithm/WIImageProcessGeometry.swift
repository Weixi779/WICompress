//
//  WIImageProcessGeometry.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

struct WIResolvedProcessGeometry: Sendable, Equatable {
    let sourceRect: Rect
    let croppedPixelSize: WIPixelSize
    let targetPixelSize: WIPixelSize

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

        let cropGeometry = try WIImageCropGeometry.resolve(
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
            sourceRect: cropGeometry.sourceRect,
            croppedPixelSize: cropGeometry.pixelSize,
            targetPixelSize: targetPixelSize
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
}
