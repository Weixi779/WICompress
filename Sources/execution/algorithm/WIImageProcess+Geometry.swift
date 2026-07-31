//
//  WIImageProcess+Geometry.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WICompressDomain
import WIImageDomain

struct ProcessGeometry: Sendable, Equatable {
    let sourceRect: Rect
    let croppedPixelSize: WIPixelSize
    let targetPixelSize: WIPixelSize

    var changesPixelSize: Bool {
        targetPixelSize != croppedPixelSize
    }
}

extension WIImageProcess {
    func geometry(
        for sourcePixelSize: WIPixelSize
    ) throws(WICompressError) -> ProcessGeometry {
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0 else {
            throw .imageInfoUnavailable
        }

        let cropGeometry = try ImageCropGeometry.resolve(
            crop,
            sourcePixelSize: sourcePixelSize
        )
        let targetPixelSize: WIPixelSize
        switch sizing {
        case .original:
            targetPixelSize = cropGeometry.pixelSize
        case .resize(let resizing):
            targetPixelSize = try resizing.targetSize(
                for: cropGeometry.pixelSize
            )
        }

        try validateExecutablePixelSize(targetPixelSize)

        return ProcessGeometry(
            sourceRect: cropGeometry.sourceRect,
            croppedPixelSize: cropGeometry.pixelSize,
            targetPixelSize: targetPixelSize
        )
    }

    private func validateExecutablePixelSize(
        _ size: WIPixelSize
    ) throws(WICompressError) {
        guard size.width > 0, size.height > 0 else {
            throw .invalidResizing
        }

        let (minimumRowBytes, rowOverflow) = size.width
            .multipliedReportingOverflow(by: 4)
        guard !rowOverflow else {
            throw .invalidResizing
        }

        let (alignmentInput, alignmentOverflow) = minimumRowBytes
            .addingReportingOverflow(63)
        guard !alignmentOverflow else {
            throw .invalidResizing
        }

        let alignedRowBytes = (alignmentInput / 64) * 64
        let (_, totalOverflow) = alignedRowBytes
            .multipliedReportingOverflow(by: size.height)
        guard !totalOverflow else {
            throw .invalidResizing
        }
    }
}
