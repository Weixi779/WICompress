//
//  ImagePipeline+Process.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/31.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

extension ImagePipeline {
    func process(
        _ process: WIImageProcess
    ) throws(WICompressError) -> WIResult {
        guard descriptor.format != .unknown else {
            throw .unsupportedSourceFormat(descriptor.type?.identifier)
        }

        try validateQuality(process.quality)

        let geometry = try WIImageProcessGeometry.resolve(
            process: process,
            sourcePixelSize: descriptor.orientedPixelSize
        )
        let output = try resolveOutput(process.output)
        let quality = output.destinationFormat.supportsLossyQuality
            ? process.quality
            : nil

        if canReturnOriginal(
            process: process,
            geometry: geometry,
            quality: quality,
            output: output
        ) {
            return try originalResult()
        }

        guard output.isWritable else {
            throw .unsupportedDestinationFormat(output.destinationFormat)
        }

        let data: Data
        if canCopyFromSource(
            process: process,
            geometry: geometry,
            quality: quality,
            output: output
        ) {
            data = try copyFromSource(
                output: output,
                metadata: process.output.metadata,
                quality: quality
            )
        } else {
            data = try renderAndEncode(
                geometry: processRender(from: geometry),
                output: output,
                metadata: process.output.metadata,
                quality: quality
            )
        }

        return try result(for: data)
    }

    private func validateQuality(
        _ quality: Double?
    ) throws(WICompressError) {
        guard let quality else {
            return
        }
        guard quality.isFinite, (0...1).contains(quality) else {
            throw .invalidProcessQuality
        }
    }

    private func canReturnOriginal(
        process: WIImageProcess,
        geometry: WIResolvedProcessGeometry,
        quality: Double?,
        output: WIResolvedImageOutput
    ) -> Bool {
        guard
            process.crop == nil,
            geometry.changesPixelSize == false,
            process.output.representation == .preserve,
            quality == nil,
            output.colorSpace.requiresConversion == false
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

    private func canCopyFromSource(
        process: WIImageProcess,
        geometry: WIResolvedProcessGeometry,
        quality: Double?,
        output: WIResolvedImageOutput
    ) -> Bool {
        process.crop == nil
            && geometry.changesPixelSize == false
            && process.output.representation == .preserve
            && output.colorSpace.requiresConversion == false
            && (
                process.output.metadata != .strip
                    || descriptor.orientation == .up
            )
            && source.canCopy(
                as: output.destinationType,
                keeping: process.output.metadata,
                compressionQuality: quality
            )
    }

    private func processRender(
        from geometry: WIResolvedProcessGeometry
    ) -> WIResolvedRender {
        let targetSize = geometry.targetPixelSize
        return WIResolvedRender(
            sourceRect: geometry.sourceRect,
            canvasSize: targetSize,
            destinationRect: Rect(
                x: 0,
                y: 0,
                width: Double(targetSize.width),
                height: Double(targetSize.height)
            ),
            canvasBackground: nil
        )
    }
}
