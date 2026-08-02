//
//  ImagePipeline+Target.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/31.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import WICompressDomain
import WIImageDomain
import WIImageIO

extension ImagePipeline {
    private static let defaultMaxEncodeAttempts = 40

    package static func compress(
        _ data: Data,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try withoutTaskCancellation {
            try self.compress(
                data,
                to: target,
                cancellation: .disabled
            )
        }
    }

    package static func compress(
        contentsOf url: URL,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try withoutTaskCancellation {
            try self.compress(
                contentsOf: url,
                to: target,
                cancellation: .disabled
            )
        }
    }

    package static func compressCancellable(
        _ data: Data,
        to target: WICompressionTarget
    ) throws -> WIResult {
        try self.compress(
            data,
            to: target,
            cancellation: .task
        )
    }

    package static func compressCancellable(
        contentsOf url: URL,
        to target: WICompressionTarget
    ) throws -> WIResult {
        try self.compress(
            contentsOf: url,
            to: target,
            cancellation: .task
        )
    }

    private static func compress(
        _ data: Data,
        to target: WICompressionTarget,
        cancellation: PipelineCancellation
    ) throws -> WIResult {
        try cancellation.check()
        let pipeline = try ImagePipeline(
            data: data,
            cancellation: cancellation
        )
        return try pipeline.compress(target)
    }

    private static func compress(
        contentsOf url: URL,
        to target: WICompressionTarget,
        cancellation: PipelineCancellation
    ) throws -> WIResult {
        try cancellation.check()
        let pipeline = try ImagePipeline(
            contentsOf: url,
            cancellation: cancellation
        )
        return try pipeline.compress(target)
    }

    func compress(
        _ target: WICompressionTarget,
        maxEncodeAttempts: Int = defaultMaxEncodeAttempts
    ) throws -> WIResult {
        try checkCancellation()

        guard descriptor.format != .unknown else {
            throw WICompressError.unsupportedSourceFormat(
                descriptor.type?.identifier
            )
        }

        let sizing = try target.sizing.geometry(for: descriptor.orientedPixelSize)
        let output = try imageDestination(target.output)
        try checkCancellation()
        if canReturnOriginal(target: target, sizing: sizing, output: output) {
            let result = try originalResult()
            try checkCancellation()
            return result
        }
        guard output.isWritable else {
            throw WICompressError.unsupportedDestinationFormat(
                output.destinationFormat
            )
        }

        let data = try compressTargetData(
            target,
            sizing: sizing,
            output: output,
            maxEncodeAttempts: maxEncodeAttempts
        )
        try checkCancellation()
        guard data.count <= target.maxBytes else {
            throw WICompressError.targetUnsatisfiable(
                smallestByteCount: data.count
            )
        }
        let result = try result(for: data)
        try checkCancellation()
        return result
    }

    private func compressTargetData(
        _ target: WICompressionTarget,
        sizing: TargetGeometry,
        output: ImageDestination,
        maxEncodeAttempts: Int
    ) throws -> Data {
        if output.destinationFormat.supportsLossyQuality {
            var search = LossyTargetSearch(
                maxBytes: target.maxBytes,
                format: output.destinationFormat,
                basePixelSize: sizing.basePixelSize,
                maxEncodeAttempts: maxEncodeAttempts,
                checkCancellation: checkCancellation
            ) { (pixelSize: WIPixelSize, initialQuality: Double) throws in
                try self.prepareTargetEncoding(
                    target: target,
                    sizing: sizing,
                    output: output,
                    pixelSize: pixelSize,
                    initialQuality: initialQuality
                )
            }
            return try search.run()
        }

        if output.destinationFormat == .png {
            var search = PNGTargetSearch(
                maxBytes: target.maxBytes,
                basePixelSize: sizing.basePixelSize,
                maxEncodeAttempts: maxEncodeAttempts,
                checkCancellation: checkCancellation
            ) { (pixelSize: WIPixelSize) throws in
                try self.prepareTargetEncoding(
                    target: target,
                    sizing: sizing,
                    output: output,
                    pixelSize: pixelSize,
                    initialQuality: nil
                )
            }
            return try search.run()
        }

        let encoding = try prepareTargetEncoding(
            target: target,
            sizing: sizing,
            output: output,
            pixelSize: sizing.basePixelSize,
            initialQuality: nil
        )
        try checkCancellation()
        let data = try encoding.encode(nil)
        try checkCancellation()
        return data
    }

    private func prepareTargetEncoding(
        target: WICompressionTarget,
        sizing: TargetGeometry,
        output: ImageDestination,
        pixelSize: WIPixelSize,
        initialQuality: Double?
    ) throws -> PreparedTargetEncoding {
        let renderedImage = try renderedImageIfNeeded(
            target: target,
            sizing: sizing,
            output: output,
            pixelSize: pixelSize,
            quality: initialQuality
        )
        let outputPixelSize = renderedImage.map {
            WIPixelSize(validWidth: $0.width, height: $0.height)
        } ?? pixelSize

        return PreparedTargetEncoding(
            pixelSize: outputPixelSize
        ) { (quality: Double?) throws in
            try self.encodeTargetCandidate(
                renderedImage,
                target: target,
                output: output,
                quality: quality
            )
        }
    }

    private func encodeTargetCandidate(
        _ renderedImage: CGImage?,
        target: WICompressionTarget,
        output: ImageDestination,
        quality: Double?
    ) throws(WICompressError) -> Data {
        if let renderedImage {
            return try encodeRendered(
                renderedImage,
                output: output,
                metadata: target.output.metadata,
                quality: quality
            )
        }
        return try transcodeSource(
            output: output,
            metadata: target.output.metadata,
            quality: quality
        )
    }

    private func renderedImageIfNeeded(
        target: WICompressionTarget,
        sizing: TargetGeometry,
        output: ImageDestination,
        pixelSize: WIPixelSize,
        quality: Double?
    ) throws -> CGImage? {
        if canTranscodeFromSource(
            target: target,
            sizing: sizing,
            output: output,
            pixelSize: pixelSize,
            quality: quality
        ) {
            return nil
        }

        return try render(
            geometry: targetRender(sizing: sizing, pixelSize: pixelSize),
            output: output
        )
    }

    private func canTranscodeFromSource(
        target: WICompressionTarget,
        sizing: TargetGeometry,
        output: ImageDestination,
        pixelSize: WIPixelSize,
        quality: Double?
    ) -> Bool {
        !sizing.hasCrop
            && pixelSize == sizing.sourcePixelSize
            && target.output.representation == .preserve
            && !output.colorSpace.requiresConversion
            && (target.output.metadata != .strip || descriptor.orientation == .up)
            && reader.canTranscode(
                as: output.destinationType,
                options: ImageTranscodeOptions(
                    compressionQuality: quality,
                    metadata: target.output.metadata
                )
            )
    }

    private func canReturnOriginal(
        target: WICompressionTarget,
        sizing: TargetGeometry,
        output: ImageDestination
    ) -> Bool {
        guard
            byteCount <= target.maxBytes,
            !sizing.hasCrop,
            sizing.basePixelSize == sizing.sourcePixelSize,
            target.output.representation == .preserve,
            !output.colorSpace.requiresConversion
        else {
            return false
        }

        let preservesUnmodeledMetadata = !descriptor.hasUnmodeledMetadata
            || target.output.metadata.preservesUnmodeledMetadata
        let preservesMetadata = descriptor.metadata.isSubset(of: target.output.metadata)
        let preservesOrientation = target.output.metadata != .strip
            || descriptor.orientation == .up
        return preservesUnmodeledMetadata && preservesMetadata && preservesOrientation
    }

    private func targetRender(
        sizing: TargetGeometry,
        pixelSize: WIPixelSize
    ) throws(WICompressError) -> RenderGeometry {
        RenderGeometry(
            sourceRect: sizing.sourceRect,
            canvasSize: pixelSize,
            destinationRect: Rect(
                x: 0,
                y: 0,
                width: Double(pixelSize.width),
                height: Double(pixelSize.height)
            ),
            canvasBackground: nil
        )
    }
}
