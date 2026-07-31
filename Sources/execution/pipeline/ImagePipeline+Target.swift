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
    private static let maxCandidateSearchEncodeAttempts = 8

    package static func compress(
        _ data: Data,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        let pipeline = try ImagePipeline(data: data)
        return try pipeline.compress(target)
    }

    package static func compress(
        contentsOf url: URL,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        let pipeline = try ImagePipeline(contentsOf: url)
        return try pipeline.compress(target)
    }

    func compress(
        _ target: WICompressionTarget,
        maxEncodeAttempts: Int = defaultMaxEncodeAttempts
    ) throws(WICompressError) -> WIResult {
        guard descriptor.format != .unknown else {
            throw .unsupportedSourceFormat(descriptor.type?.identifier)
        }

        let sizing = try target.sizing.geometry(
            for: descriptor.orientedPixelSize
        )
        let output = try imageDestination(target.output)

        if canReturnOriginal(
            target: target,
            sizing: sizing,
            output: output
        ) {
            return try originalResult()
        }

        guard output.isWritable else {
            throw .unsupportedDestinationFormat(output.destinationFormat)
        }

        let data = try compressTargetData(
            target,
            sizing: sizing,
            output: output,
            maxEncodeAttempts: maxEncodeAttempts
        )
        guard data.count <= target.maxBytes else {
            throw .targetUnsatisfiable(
                smallestByteCount: data.count
            )
        }

        return try result(for: data)
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

        return (
            !descriptor.hasUnmodeledMetadata
                || target.output.metadata.preservesUnmodeledMetadata
        )
            && descriptor.metadata.isSubset(of: target.output.metadata)
            && (
                target.output.metadata != .strip
                    || descriptor.orientation == .up
            )
    }

    private func compressTargetData(
        _ target: WICompressionTarget,
        sizing: TargetGeometry,
        output: ImageDestination,
        maxEncodeAttempts: Int
    ) throws(WICompressError) -> Data {
        guard output.destinationFormat.supportsLossyQuality else {
            if output.destinationFormat == .png {
                return try searchLossless(
                    target: target,
                    sizing: sizing,
                    output: output,
                    maxEncodeAttempts: maxEncodeAttempts
                )
            }

            let image = try renderedImageIfNeeded(
                target: target,
                sizing: sizing,
                output: output,
                pixelSize: sizing.basePixelSize,
                quality: nil
            )
            return try encodeCandidate(
                image,
                target: target,
                output: output,
                quality: nil
            )
        }

        let profile = WILossyQualityProfile(
            format: output.destinationFormat
        )
        let referencePixelSize = sizing.basePixelSize
        var currentLongSide = max(
            sizing.basePixelSize.width,
            sizing.basePixelSize.height
        )
        var longSideOverride: Int?
        var highQuality = profile.qHigh
        var attemptCount = 0
        var smallestByteCount: Int?
        var candidates: [WISolvedCompressionCandidate] = []

        while true {
            if shouldReturnBestCandidate(
                candidates,
                attemptCount: attemptCount,
                maxEncodeAttempts: maxEncodeAttempts
            ) {
                return WICompressionRanking.bestCandidate(
                    candidates,
                    referencePixelSize: referencePixelSize
                ).data
            }

            let pixelSize = candidatePixelSize(
                sizing: sizing,
                maxLongSide: longSideOverride
            )
            let renderedImage = try renderedImageIfNeeded(
                target: target,
                sizing: sizing,
                output: output,
                pixelSize: pixelSize,
                quality: highQuality
            )
            let outputPixelSize = renderedImage.map {
                WIPixelSize(validWidth: $0.width, height: $0.height)
            } ?? pixelSize
            let outcome: FixedSizeOutcome
            do {
                outcome = try searchFixedSize(
                    target: target,
                    output: output,
                    renderedImage: renderedImage,
                    outputPixelSize: outputPixelSize,
                    profile: profile,
                    highQuality: highQuality,
                    attemptCount: &attemptCount,
                    maxEncodeAttempts: maxEncodeAttempts
                )
            } catch WICompressError.resourceLimitExceeded {
                if !candidates.isEmpty {
                    return WICompressionRanking.bestCandidate(
                        candidates,
                        referencePixelSize: referencePixelSize
                    ).data
                }
                throw WICompressError.resourceLimitExceeded(
                    attemptCount: attemptCount
                )
            }

            if let candidate = outcome.candidate {
                candidates.append(candidate)
                if candidate.quality >= highQuality {
                    return WICompressionRanking.bestCandidate(
                        candidates,
                        referencePixelSize: referencePixelSize
                    ).data
                }
            }

            smallestByteCount = minByteCount(
                smallestByteCount,
                outcome.smallestByteCount
            )
            guard
                let estimateByteCount = outcome.dimensionSearchByteCount
                    ?? outcome.smallestByteCount,
                let nextLongSide = WICompressionSizeEstimation.nextLongSide(
                    current: currentLongSide,
                    encodedBytes: estimateByteCount,
                    maxBytes: target.maxBytes,
                    format: output.destinationFormat
                )
            else {
                if !candidates.isEmpty {
                    return WICompressionRanking.bestCandidate(
                        candidates,
                        referencePixelSize: referencePixelSize
                    ).data
                }
                throw WICompressError.targetUnsatisfiable(
                    smallestByteCount: smallestByteCount
                )
            }

            currentLongSide = nextLongSide
            longSideOverride = nextLongSide
            highQuality = profile.qAnchor
        }
    }

    private func searchLossless(
        target: WICompressionTarget,
        sizing: TargetGeometry,
        output: ImageDestination,
        maxEncodeAttempts: Int
    ) throws(WICompressError) -> Data {
        var currentLongSide = max(
            sizing.basePixelSize.width,
            sizing.basePixelSize.height
        )
        var longSideOverride: Int?
        var attemptCount = 0
        var smallestByteCount: Int?

        while true {
            let pixelSize = candidatePixelSize(
                sizing: sizing,
                maxLongSide: longSideOverride
            )
            let renderedImage = try renderedImageIfNeeded(
                target: target,
                sizing: sizing,
                output: output,
                pixelSize: pixelSize,
                quality: nil
            )
            let data = try encodeCandidate(
                renderedImage,
                target: target,
                output: output,
                quality: nil,
                attemptCount: &attemptCount,
                maxEncodeAttempts: maxEncodeAttempts
            )

            if data.count <= target.maxBytes {
                return data
            }

            smallestByteCount = minByteCount(
                smallestByteCount,
                data.count
            )
            guard let nextLongSide = WICompressionSizeEstimation.nextLongSide(
                current: currentLongSide,
                encodedBytes: data.count,
                maxBytes: target.maxBytes,
                format: output.destinationFormat
            ) else {
                throw WICompressError.targetUnsatisfiable(
                    smallestByteCount: smallestByteCount
                )
            }

            currentLongSide = nextLongSide
            longSideOverride = nextLongSide
        }
    }

    private func searchFixedSize(
        target: WICompressionTarget,
        output: ImageDestination,
        renderedImage: CGImage?,
        outputPixelSize: WIPixelSize,
        profile: WILossyQualityProfile,
        highQuality: Double,
        attemptCount: inout Int,
        maxEncodeAttempts: Int
    ) throws(WICompressError) -> FixedSizeOutcome {
        let highData = try encodeCandidate(
            renderedImage,
            target: target,
            output: output,
            quality: highQuality,
            attemptCount: &attemptCount,
            maxEncodeAttempts: maxEncodeAttempts
        )
        if highData.count <= target.maxBytes {
            return FixedSizeOutcome(
                candidate: WISolvedCompressionCandidate(
                    data: highData,
                    pixelSize: outputPixelSize,
                    format: output.destinationFormat,
                    quality: highQuality
                ),
                smallestByteCount: highData.count,
                dimensionSearchByteCount: nil
            )
        }

        let kneeData = try encodeCandidate(
            renderedImage,
            target: target,
            output: output,
            quality: profile.qKnee,
            attemptCount: &attemptCount,
            maxEncodeAttempts: maxEncodeAttempts
        )
        if kneeData.count <= target.maxBytes {
            let candidate = try searchQuality(
                target: target,
                output: output,
                renderedImage: renderedImage,
                lowQuality: profile.qKnee,
                highQuality: highQuality,
                lowData: kneeData,
                outputPixelSize: outputPixelSize,
                attemptCount: &attemptCount,
                maxEncodeAttempts: maxEncodeAttempts
            )
            return FixedSizeOutcome(
                candidate: candidate,
                smallestByteCount: kneeData.count,
                dimensionSearchByteCount: highData.count
            )
        }

        return FixedSizeOutcome(
            candidate: nil,
            smallestByteCount: min(highData.count, kneeData.count),
            dimensionSearchByteCount: min(highData.count, kneeData.count)
        )
    }

    private func searchQuality(
        target: WICompressionTarget,
        output: ImageDestination,
        renderedImage: CGImage?,
        lowQuality: Double,
        highQuality: Double,
        lowData: Data,
        outputPixelSize: WIPixelSize,
        attemptCount: inout Int,
        maxEncodeAttempts: Int
    ) throws(WICompressError) -> WISolvedCompressionCandidate {
        var lowerBound = lowQuality
        var upperBound = highQuality
        var bestData = lowData
        var bestQuality = lowQuality

        for _ in 0..<6 {
            let quality = (lowerBound + upperBound) / 2
            let data = try encodeCandidate(
                renderedImage,
                target: target,
                output: output,
                quality: quality,
                attemptCount: &attemptCount,
                maxEncodeAttempts: maxEncodeAttempts
            )

            if data.count <= target.maxBytes {
                lowerBound = quality
                bestData = data
                bestQuality = quality
            } else {
                upperBound = quality
            }
        }

        return WISolvedCompressionCandidate(
            data: bestData,
            pixelSize: outputPixelSize,
            format: output.destinationFormat,
            quality: bestQuality
        )
    }

    private func encodeCandidate(
        _ renderedImage: CGImage?,
        target: WICompressionTarget,
        output: ImageDestination,
        quality: Double?,
        attemptCount: inout Int,
        maxEncodeAttempts: Int
    ) throws(WICompressError) -> Data {
        guard attemptCount < maxEncodeAttempts else {
            throw WICompressError.resourceLimitExceeded(
                attemptCount: attemptCount
            )
        }

        attemptCount += 1
        return try encodeCandidate(
            renderedImage,
            target: target,
            output: output,
            quality: quality
        )
    }

    private func encodeCandidate(
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

        return try copyFromSource(
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
    ) throws(WICompressError) -> CGImage? {
        if canCopyFromSource(
            target: target,
            sizing: sizing,
            output: output,
            pixelSize: pixelSize,
            quality: quality
        ) {
            return nil
        }

        return try render(
            geometry: targetRender(
                sizing: sizing,
                pixelSize: pixelSize
            ),
            output: output
        )
    }

    private func canCopyFromSource(
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
            && (
                target.output.metadata != .strip
                    || descriptor.orientation == .up
            )
            && reader.canCopy(
                as: output.destinationType,
                options: WIImageIO.CopyOptions(
                    compressionQuality: quality,
                    metadata: target.output.metadata
                )
            )
    }

    private func targetRender(
        sizing: TargetGeometry,
        pixelSize: WIPixelSize
    ) throws(WICompressError) -> RenderGeometry {
        return RenderGeometry(
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

    private func candidatePixelSize(
        sizing: TargetGeometry,
        maxLongSide: Int?
    ) -> WIPixelSize {
        guard let maxLongSide else {
            return sizing.basePixelSize
        }

        return WICompressionSizeEstimation.scaledPixelSize(
            source: sizing.basePixelSize,
            maxLongSide: maxLongSide
        )
    }

    private func shouldReturnBestCandidate(
        _ candidates: [WISolvedCompressionCandidate],
        attemptCount: Int,
        maxEncodeAttempts: Int
    ) -> Bool {
        guard !candidates.isEmpty else {
            return false
        }

        let remainingAttempts = max(
            maxEncodeAttempts - attemptCount,
            0
        )
        return remainingAttempts < Self.maxCandidateSearchEncodeAttempts
    }

    private func minByteCount(
        _ lhs: Int?,
        _ rhs: Int?
    ) -> Int? {
        switch (lhs, rhs) {
        case (.some(let lhs), .some(let rhs)):
            return min(lhs, rhs)
        case (.some(let lhs), .none):
            return lhs
        case (.none, .some(let rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }
}

private struct FixedSizeOutcome: Sendable, Equatable {
    var candidate: WISolvedCompressionCandidate?
    var smallestByteCount: Int?
    var dimensionSearchByteCount: Int?
}
