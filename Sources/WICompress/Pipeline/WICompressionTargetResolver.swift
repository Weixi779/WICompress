//
//  WICompressionTargetResolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Builds the encoder inputs (`WICompressOptions` / `WIWritePlan`) for a target.
///
/// Legality is checked separately by `WICompressionTargetValidator`; placement
/// math comes from `WICompressionLayout`. This type only wires those into the
/// existing `WIWritePlanResolver` and chooses the canvas vs. soft-resize path.
enum WICompressionTargetResolver {
    private static let defaultTargetQuality = WIQualityPolicy.compression(0.6)

    static func options(for target: WICompressionTarget) throws(WICompressError) -> WICompressOptions {
        guard let resize = resizePolicy(for: target.geometry) else {
            throw WICompressError.unsupportedCompressionGeometry(target.geometry)
        }

        return WICompressOptions(
            resize: resize,
            format: target.output.format,
            metadata: target.output.metadata,
            quality: defaultTargetQuality,
            colorSpace: target.output.colorSpace
        )
    }

    static func writePlan(
        for target: WICompressionTarget,
        info: WIImageInfo,
        sourceColorSpace: WISourceColorSpaceInfo?
    ) throws(WICompressError) -> WIWritePlan {
        guard let renderGeometry = renderGeometry(for: target.geometry, info: info) else {
            let options = try options(for: target)
            return try WIWritePlanResolver.resolve(
                options: options,
                info: info,
                sourceColorSpace: sourceColorSpace
            )
        }

        let destination = try WIWritePlanResolver.resolvedDestination(
            for: target.output.format,
            info: info
        )
        let canWriteDestination = target.output.format == .preserve
            ? info.isSourceFormatWritable
            : WIImageFormat.canWrite(typeIdentifier: destination.typeIdentifier)
        guard canWriteDestination else {
            throw WICompressError.unsupportedDestinationFormat(destination.format)
        }

        let quality = WIWritePlanResolver.resolvedQuality(
            for: defaultTargetQuality,
            destinationFormat: destination.format
        )
        let colorSpace = try WIWritePlanResolver.resolvedColorSpace(
            for: target.output.colorSpace,
            sourceColorSpace: sourceColorSpace
        )

        return WIWritePlan(
            path: .redrawCanvas,
            destinationFormat: destination.format,
            destinationTypeIdentifier: destination.typeIdentifier,
            maxPixelSize: nil,
            targetPixelSize: renderGeometry.canvasSize,
            renderGeometry: renderGeometry,
            metadataPolicy: target.output.metadata,
            quality: quality,
            jpegBackground: destination.jpegBackground,
            outputColorSpace: colorSpace
        )
    }

    private static func resizePolicy(for geometry: WICompressionGeometry) -> WIResizePolicy? {
        switch geometry {
        case .original:
            return WIResizePolicy.none
        case .fit(let maxLongSide):
            return .maxPixel(maxLongSide)
        case .fitInside(let box):
            return .fit(minSize: WISize(width: 1, height: 1), maxSize: box)
        case .fill, .exactCanvas:
            return nil
        }
    }

    private static func renderGeometry(
        for geometry: WICompressionGeometry,
        info: WIImageInfo
    ) -> WIRenderGeometry? {
        let sourceSize = WIPixelSize(width: info.displayWidth, height: info.displayHeight)

        switch geometry {
        case .fill(let size, let crop):
            let canvasSize = WIPixelSize(size)
            return WIRenderGeometry(
                canvasSize: canvasSize,
                destinationRect: WICompressionLayout.destinationRect(
                    sourceSize: sourceSize,
                    canvasSize: canvasSize,
                    placement: .fill(crop)
                ),
                background: nil
            )
        case .exactCanvas(let size, let placement, let background):
            let canvasSize = WIPixelSize(size)
            return WIRenderGeometry(
                canvasSize: canvasSize,
                destinationRect: WICompressionLayout.destinationRect(
                    sourceSize: sourceSize,
                    canvasSize: canvasSize,
                    placement: placement
                ),
                background: background
            )
        case .original, .fit, .fitInside:
            return nil
        }
    }
}
