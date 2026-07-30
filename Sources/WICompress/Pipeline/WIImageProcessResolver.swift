//
//  WIImageProcessResolver.swift
//  WICompress
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

enum WIImageProcessResolver {
    static func resolve(
        _ process: WIImageProcess,
        imageSource: WIImageSource
    ) throws(WICompressError) -> WIExecutionPlan {
        let info = imageSource.info
        guard info.sourceFormat != .unknown else {
            throw .unsupportedSourceFormat(info.typeIdentifier)
        }

        try validateQuality(process.quality)

        let geometry = try WIImageProcessGeometry.resolve(
            process: process,
            sourcePixelSize: WIPixelSize(
                width: info.displayWidth,
                height: info.displayHeight
            )
        )
        let resolvedOutput = try WIImageOutputResolver.resolve(
            process.output,
            imageSource: imageSource
        )
        let quality = resolvedOutput.destinationFormat.supportsLossyQuality
            ? process.quality
            : nil

        if canReturnOriginal(
            process: process,
            geometry: geometry,
            quality: quality,
            info: info,
            outputColorSpace: resolvedOutput.colorSpace
        ) {
            return plan(
                operation: .returnOriginal,
                resolvedOutput: resolvedOutput,
                process: process,
                quality: quality
            )
        }

        guard resolvedOutput.isWritable else {
            throw .unsupportedDestinationFormat(
                resolvedOutput.destinationFormat
            )
        }

        let operation: WIExecutionPlan.Operation
        if canCopyFromSource(
            process: process,
            geometry: geometry,
            outputColorSpace: resolvedOutput.colorSpace
        ) {
            operation = .copyFromSource
        } else {
            let targetSize = geometry.targetPixelSize
            operation = .render(
                WIResolvedRender(
                    sourceRect: geometry.sourceRect,
                    canvasSize: targetSize,
                    destinationRect: WIRect(
                        x: 0,
                        y: 0,
                        width: Double(targetSize.width),
                        height: Double(targetSize.height)
                    ),
                    canvasBackground: nil
                )
            )
        }

        return plan(
            operation: operation,
            resolvedOutput: resolvedOutput,
            process: process,
            quality: quality
        )
    }

    private static func validateQuality(
        _ quality: Double?
    ) throws(WICompressError) {
        guard let quality else {
            return
        }
        guard quality.isFinite, (0...1).contains(quality) else {
            throw .invalidProcessQuality
        }
    }

    private static func canReturnOriginal(
        process: WIImageProcess,
        geometry: WIResolvedProcessGeometry,
        quality: Double?,
        info: WIImageInfo,
        outputColorSpace: WIResolvedOutputColorSpace
    ) -> Bool {
        guard
            process.crop == nil,
            geometry.changesPixelSize == false,
            process.output.representation == .preserve,
            quality == nil,
            outputColorSpace.requiresConversion == false
        else {
            return false
        }

        switch process.output.metadata {
        case .preserve:
            return true
        case .strip:
            return !info.hasMetadata && info.orientation == 1
        }
    }

    private static func canCopyFromSource(
        process: WIImageProcess,
        geometry: WIResolvedProcessGeometry,
        outputColorSpace: WIResolvedOutputColorSpace
    ) -> Bool {
        process.crop == nil
            && geometry.changesPixelSize == false
            && process.output.representation == .preserve
            && process.output.metadata == .preserve
            && outputColorSpace.requiresConversion == false
    }

    private static func plan(
        operation: WIExecutionPlan.Operation,
        resolvedOutput: WIResolvedImageOutput,
        process: WIImageProcess,
        quality: Double?
    ) -> WIExecutionPlan {
        WIExecutionPlan(
            operation: operation,
            destinationFormat: resolvedOutput.destinationFormat,
            destinationTypeIdentifier: resolvedOutput.destinationTypeIdentifier,
            metadata: process.output.metadata,
            quality: quality,
            jpegBackground: resolvedOutput.jpegBackground,
            outputColorSpace: resolvedOutput.colorSpace
        )
    }
}
