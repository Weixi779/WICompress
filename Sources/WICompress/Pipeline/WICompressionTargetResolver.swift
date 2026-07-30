//
//  WICompressionTargetResolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageCore

enum WICompressionTargetResolver {
    static func sizing(
        for target: WICompressionTarget,
        imageSource: WIImageSource
    ) throws(WICompressError) -> WIResolvedCompressionSizing {
        guard imageSource.info.sourceFormat != .unknown else {
            throw .unsupportedSourceFormat(
                imageSource.info.typeIdentifier
            )
        }

        return try WICompressionSizingResolver.resolve(
            target.sizing,
            sourcePixelSize: WIPixelSize(
                width: imageSource.info.displayWidth,
                height: imageSource.info.displayHeight
            )
        )
    }

    static func output(
        for target: WICompressionTarget,
        imageSource: WIImageSource
    ) throws(WICompressError) -> WIResolvedImageOutput {
        try WIImageOutputResolver.resolve(
            target.output,
            imageSource: imageSource
        )
    }

    static func canReturnOriginal(
        target: WICompressionTarget,
        sizing: WIResolvedCompressionSizing,
        output: WIResolvedImageOutput,
        imageSource: WIImageSource
    ) -> Bool {
        guard
            imageSource.byteCount <= target.maxBytes,
            !sizing.hasCrop,
            sizing.basePixelSize == sizing.sourcePixelSize,
            target.output.representation == .preserve,
            !output.colorSpace.requiresConversion
        else {
            return false
        }

        switch target.output.metadata {
        case .preserve:
            return true
        case .strip:
            return !imageSource.info.hasMetadata
                && imageSource.info.orientation == .up
        }
    }

    static func executionPlan(
        for target: WICompressionTarget,
        sizing: WIResolvedCompressionSizing,
        output: WIResolvedImageOutput,
        pixelSize: WIPixelSize,
        quality: Double?
    ) throws(WICompressError) -> WIExecutionPlan {
        guard output.isWritable else {
            throw .unsupportedDestinationFormat(
                WIImageFormat(output.destinationFormat)
            )
        }

        let resolvedQuality = output.destinationFormat.supportsLossyQuality
            ? quality
            : nil
        let operation: WIExecutionPlan.Operation
        if canCopyFromSource(
            target: target,
            sizing: sizing,
            output: output,
            pixelSize: pixelSize
        ) {
            operation = .copyFromSource
        } else {
            let canvasSize: PixelSize
            do {
                canvasSize = try PixelSize(
                    width: pixelSize.width,
                    height: pixelSize.height
                )
            } catch {
                throw .invalidTarget
            }
            operation = .render(
                WIResolvedRender(
                    sourceRect: sizing.sourceRect,
                    canvasSize: canvasSize,
                    destinationRect: Rect(
                        x: 0,
                        y: 0,
                        width: Double(pixelSize.width),
                        height: Double(pixelSize.height)
                    ),
                    canvasBackground: nil
                )
            )
        }

        return WIExecutionPlan(
            operation: operation,
            destinationFormat: output.destinationFormat,
            destinationTypeIdentifier: output.destinationTypeIdentifier,
            metadata: target.output.metadata,
            quality: resolvedQuality,
            jpegBackground: output.jpegBackground,
            outputColorSpace: output.colorSpace
        )
    }

    private static func canCopyFromSource(
        target: WICompressionTarget,
        sizing: WIResolvedCompressionSizing,
        output: WIResolvedImageOutput,
        pixelSize: WIPixelSize
    ) -> Bool {
        !sizing.hasCrop
            && pixelSize == sizing.sourcePixelSize
            && target.output.representation == .preserve
            && target.output.metadata == .preserve
            && !output.colorSpace.requiresConversion
    }
}
