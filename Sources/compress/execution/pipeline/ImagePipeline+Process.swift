//
//  ImagePipeline+Process.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/31.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WICompressDomain
import WIImageDomain
import WIImageIO

extension ImagePipeline {
    package static func process(
        _ data: Data,
        using process: WIImageProcess
    ) throws(WICompressError) -> WIResult {
        try withoutTaskCancellation {
            try self.process(
                data,
                using: process,
                cancellation: .disabled
            )
        }
    }

    package static func process(
        contentsOf url: URL,
        using process: WIImageProcess
    ) throws(WICompressError) -> WIResult {
        try withoutTaskCancellation {
            try self.process(
                contentsOf: url,
                using: process,
                cancellation: .disabled
            )
        }
    }

    package static func processCancellable(
        _ data: Data,
        using process: WIImageProcess
    ) throws -> WIResult {
        try self.process(
            data,
            using: process,
            cancellation: .task
        )
    }

    package static func processCancellable(
        contentsOf url: URL,
        using process: WIImageProcess
    ) throws -> WIResult {
        try self.process(
            contentsOf: url,
            using: process,
            cancellation: .task
        )
    }

    private static func process(
        _ data: Data,
        using process: WIImageProcess,
        cancellation: PipelineCancellation
    ) throws -> WIResult {
        try cancellation.check()
        let pipeline = try ImagePipeline(
            data: data,
            cancellation: cancellation
        )
        return try pipeline.process(process)
    }

    private static func process(
        contentsOf url: URL,
        using process: WIImageProcess,
        cancellation: PipelineCancellation
    ) throws -> WIResult {
        try cancellation.check()
        let pipeline = try ImagePipeline(
            contentsOf: url,
            cancellation: cancellation
        )
        return try pipeline.process(process)
    }

    private func process(
        _ process: WIImageProcess
    ) throws -> WIResult {
        try checkCancellation()

        guard descriptor.format != .unknown else {
            throw WICompressError.unsupportedSourceFormat(
                descriptor.type?.identifier
            )
        }

        let geometry = try process.geometry(
            for: descriptor.orientedPixelSize
        )
        let output = try imageDestination(process.output)
        let quality = output.destinationFormat.supportsLossyQuality
            ? process.quality
            : nil
        try checkCancellation()

        if canReturnOriginal(
            process: process,
            geometry: geometry,
            quality: quality,
            output: output
        ) {
            let result = try originalResult()
            try checkCancellation()
            return result
        }

        guard output.isWritable else {
            throw WICompressError.unsupportedDestinationFormat(
                output.destinationFormat
            )
        }

        try checkCancellation()
        let data: Data
        if canTranscodeFromSource(
            process: process,
            geometry: geometry,
            quality: quality,
            output: output
        ) {
            data = try transcodeSource(
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
        try checkCancellation()

        let result = try result(for: data)
        try checkCancellation()
        return result
    }

    private func canReturnOriginal(
        process: WIImageProcess,
        geometry: ProcessGeometry,
        quality: Double?,
        output: ImageDestination
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

    private func canTranscodeFromSource(
        process: WIImageProcess,
        geometry: ProcessGeometry,
        quality: Double?,
        output: ImageDestination
    ) -> Bool {
        process.crop == nil
            && geometry.changesPixelSize == false
            && process.output.representation == .preserve
            && output.colorSpace.requiresConversion == false
            && (
                process.output.metadata != .strip
                    || descriptor.orientation == .up
            )
            && reader.canTranscode(
                as: output.destinationType,
                options: ImageTranscodeOptions(
                    compressionQuality: quality,
                    metadata: process.output.metadata
                )
            )
    }

    private func processRender(
        from geometry: ProcessGeometry
    ) -> RenderGeometry {
        let targetSize = geometry.targetPixelSize
        return RenderGeometry(
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
