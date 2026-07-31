//
//  WICompressionTargetResolver.swift
//  WICompressExecution
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain
import WIImageIO

enum WICompressionTargetResolver {
    static func sizing(
        for target: WICompressionTarget,
        imageSource: WIImageSource
    ) throws(WICompressError) -> WIResolvedCompressionSizing {
        let descriptor = imageSource.descriptor
        guard descriptor.format != .unknown else {
            throw .unsupportedSourceFormat(
                descriptor.type?.identifier
            )
        }

        return try WICompressionSizingResolver.resolve(
            target.sizing,
            sourcePixelSize: descriptor.orientedPixelSize
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

        return (
            !imageSource.descriptor.hasUnmodeledMetadata
                || target.output.metadata.preservesUnmodeledMetadata
        )
            && imageSource.descriptor.metadata.isSubset(
                of: target.output.metadata
            ) && (
            target.output.metadata != .strip
                || imageSource.descriptor.orientation == .up
        )
    }

    static func executionPlan(
        for target: WICompressionTarget,
        sizing: WIResolvedCompressionSizing,
        output: WIResolvedImageOutput,
        imageSource: WIImageSource,
        pixelSize: WIPixelSize,
        quality: Double?
    ) throws(WICompressError) -> WIExecutionPlan {
        guard output.isWritable else {
            throw .unsupportedDestinationFormat(output.destinationFormat)
        }

        let resolvedQuality = output.destinationFormat.supportsLossyQuality
            ? quality
            : nil
        let operation: WIExecutionPlan.Operation
        if canCopyFromSource(
            target: target,
            sizing: sizing,
            output: output,
            imageSource: imageSource,
            pixelSize: pixelSize,
            quality: resolvedQuality
        ) {
            operation = .copyFromSource
        } else {
            let canvasSize: WIPixelSize
            do {
                canvasSize = try WIPixelSize(
                    validatingWidth: pixelSize.width,
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
            destinationType: output.destinationType,
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
        imageSource: WIImageSource,
        pixelSize: WIPixelSize,
        quality: Double?
    ) -> Bool {
        !sizing.hasCrop
            && pixelSize == sizing.sourcePixelSize
            && target.output.representation == .preserve
            && !output.colorSpace.requiresConversion
            && (
                target.output.metadata != .strip
                    || imageSource.descriptor.orientation == .up
            )
            && imageSource.imageIOSource.canCopy(
                as: output.destinationType,
                keeping: target.output.metadata,
                compressionQuality: quality
            )
    }
}
