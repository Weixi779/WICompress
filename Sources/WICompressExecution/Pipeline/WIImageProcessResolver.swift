//
//  WIImageProcessResolver.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import UniformTypeIdentifiers
import WIImageDomain
import WIImageIO

enum WIImageProcessResolver {
    static func resolve(
        _ process: WIImageProcess,
        pipeline: ImagePipeline
    ) throws(WICompressError) -> WIExecutionPlan {
        let descriptor = pipeline.descriptor
        guard descriptor.format != .unknown else {
            throw .unsupportedSourceFormat(descriptor.type?.identifier)
        }

        try validateQuality(process.quality)

        let geometry = try WIImageProcessGeometry.resolve(
            process: process,
            sourcePixelSize: descriptor.orientedPixelSize
        )
        let resolvedOutput = try WIImageOutputResolver.resolve(
            process.output,
            pipeline: pipeline
        )
        let quality = resolvedOutput.destinationFormat.supportsLossyQuality
            ? process.quality
            : nil

        if canReturnOriginal(
            process: process,
            geometry: geometry,
            quality: quality,
            descriptor: descriptor,
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
            throw .unsupportedDestinationFormat(resolvedOutput.destinationFormat)
        }

        let operation: WIExecutionPlan.Operation
        if canCopyFromSource(
            process: process,
            geometry: geometry,
            pipeline: pipeline,
            quality: quality,
            destinationType: resolvedOutput.destinationType,
            outputColorSpace: resolvedOutput.colorSpace
        ) {
            operation = .copyFromSource
        } else {
            let targetSize = geometry.targetPixelSize
            let canvasSize: WIPixelSize
            do {
                canvasSize = try WIPixelSize(
                    validatingWidth: targetSize.width,
                    height: targetSize.height
                )
            } catch {
                throw .invalidResizingResult
            }
            operation = .render(
                WIResolvedRender(
                    sourceRect: geometry.sourceRect,
                    canvasSize: canvasSize,
                    destinationRect: Rect(
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
        descriptor: WIImageIO.Descriptor,
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

        return (
            !descriptor.hasUnmodeledMetadata
                || process.output.metadata.preservesUnmodeledMetadata
        )
            && descriptor.metadata.isSubset(of: process.output.metadata)
            && (
                process.output.metadata != .strip
                    || descriptor.orientation == .up
            )
    }

    private static func canCopyFromSource(
        process: WIImageProcess,
        geometry: WIResolvedProcessGeometry,
        pipeline: ImagePipeline,
        quality: Double?,
        destinationType: UTType,
        outputColorSpace: WIResolvedOutputColorSpace
    ) -> Bool {
        process.crop == nil
            && geometry.changesPixelSize == false
            && process.output.representation == .preserve
            && outputColorSpace.requiresConversion == false
            && (
                process.output.metadata != .strip
                    || pipeline.descriptor.orientation == .up
            )
            && pipeline.source.canCopy(
                as: destinationType,
                keeping: process.output.metadata,
                compressionQuality: quality
            )
    }

    private static func plan(
        operation: WIExecutionPlan.Operation,
        resolvedOutput: WIResolvedImageOutput,
        process: WIImageProcess,
        quality: Double?
    ) -> WIExecutionPlan {
        WIExecutionPlan(
            operation: operation,
            destinationType: resolvedOutput.destinationType,
            metadata: process.output.metadata,
            quality: quality,
            jpegBackground: resolvedOutput.jpegBackground,
            outputColorSpace: resolvedOutput.colorSpace
        )
    }
}
