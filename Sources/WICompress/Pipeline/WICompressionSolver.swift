//
//  WICompressionSolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import WIImageCore

/// Target byte-budget search over one fixed crop and a uniformly scaled base size.
enum WICompressionSolver {
    private static let defaultMaxEncodeAttempts = 40
    private static let maxCandidateSearchEncodeAttempts = 8
    private static let defaultTargetQuality = 0.6

    static func compress(
        _ imageSource: WIImageSource,
        to target: WICompressionTarget,
        maxEncodeAttempts: Int = defaultMaxEncodeAttempts
    ) throws(WICompressError) -> Data {
        try WICompressionTargetValidator.validate(target)
        let sizing = try WICompressionTargetResolver.sizing(
            for: target,
            imageSource: imageSource
        )
        let output = try WICompressionTargetResolver.output(
            for: target,
            imageSource: imageSource
        )
        return try compress(
            imageSource,
            to: target,
            sizing: sizing,
            output: output,
            maxEncodeAttempts: maxEncodeAttempts
        )
    }

    static func compress(
        _ imageSource: WIImageSource,
        to target: WICompressionTarget,
        sizing: WIResolvedCompressionSizing,
        output: WIResolvedImageOutput,
        maxEncodeAttempts: Int = defaultMaxEncodeAttempts
    ) throws(WICompressError) -> Data {
        let initialPlan = try WICompressionTargetResolver.executionPlan(
            for: target,
            sizing: sizing,
            output: output,
            pixelSize: sizing.basePixelSize,
            quality: defaultTargetQuality
        )

        guard initialPlan.destinationFormat.supportsLossyQuality,
              initialPlan.quality != nil else {
            if initialPlan.destinationFormat == .png {
                return try solveLossless(
                    imageSource,
                    target: target,
                    sizing: sizing,
                    output: output,
                    maxEncodeAttempts: maxEncodeAttempts
                )
            }

            return try WIImageEncoder.encode(
                imageSource,
                plan: initialPlan
            )
        }

        let profile = WILossyQualityProfile(
            format: initialPlan.destinationFormat
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
            let plan = try WICompressionTargetResolver.executionPlan(
                for: target,
                sizing: sizing,
                output: output,
                pixelSize: pixelSize,
                quality: highQuality
            )
            let renderedImage = try renderedImageIfNeeded(
                imageSource,
                plan: plan
            )
            let outputPixelSize = renderedImage.map {
                WIPixelSize(width: $0.width, height: $0.height)
            } ?? pixelSize
            let outcome: WIFixedSizeSolveOutcome
            do {
                outcome = try solveFixedSize(
                    imageSource,
                    plan: plan,
                    renderedImage: renderedImage,
                    outputPixelSize: outputPixelSize,
                    maxBytes: target.maxBytes,
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
                    format: plan.destinationFormat
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

    private static func solveLossless(
        _ imageSource: WIImageSource,
        target: WICompressionTarget,
        sizing: WIResolvedCompressionSizing,
        output: WIResolvedImageOutput,
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
            let plan = try WICompressionTargetResolver.executionPlan(
                for: target,
                sizing: sizing,
                output: output,
                pixelSize: pixelSize,
                quality: nil
            )
            let renderedImage = try renderedImageIfNeeded(
                imageSource,
                plan: plan
            )
            let data = try encode(
                imageSource,
                plan: plan,
                renderedImage: renderedImage,
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
                format: plan.destinationFormat
            ) else {
                throw WICompressError.targetUnsatisfiable(
                    smallestByteCount: smallestByteCount
                )
            }

            currentLongSide = nextLongSide
            longSideOverride = nextLongSide
        }
    }

    private static func solveFixedSize(
        _ imageSource: WIImageSource,
        plan: WIExecutionPlan,
        renderedImage: CGImage?,
        outputPixelSize: WIPixelSize,
        maxBytes: Int,
        profile: WILossyQualityProfile,
        highQuality: Double,
        attemptCount: inout Int,
        maxEncodeAttempts: Int
    ) throws(WICompressError) -> WIFixedSizeSolveOutcome {
        let highData = try encode(
            imageSource,
            plan: plan,
            renderedImage: renderedImage,
            quality: highQuality,
            attemptCount: &attemptCount,
            maxEncodeAttempts: maxEncodeAttempts
        )
        if highData.count <= maxBytes {
            return WIFixedSizeSolveOutcome(
                candidate: WISolvedCompressionCandidate(
                    data: highData,
                    pixelSize: outputPixelSize,
                    format: plan.destinationFormat,
                    quality: highQuality
                ),
                smallestByteCount: highData.count,
                dimensionSearchByteCount: nil
            )
        }

        let kneeData = try encode(
            imageSource,
            plan: plan,
            renderedImage: renderedImage,
            quality: profile.qKnee,
            attemptCount: &attemptCount,
            maxEncodeAttempts: maxEncodeAttempts
        )
        if kneeData.count <= maxBytes {
            let candidate = try searchQuality(
                imageSource,
                plan: plan,
                renderedImage: renderedImage,
                maxBytes: maxBytes,
                lowQuality: profile.qKnee,
                highQuality: highQuality,
                lowData: kneeData,
                outputPixelSize: outputPixelSize,
                destinationFormat: plan.destinationFormat,
                attemptCount: &attemptCount,
                maxEncodeAttempts: maxEncodeAttempts
            )
            return WIFixedSizeSolveOutcome(
                candidate: candidate,
                smallestByteCount: kneeData.count,
                dimensionSearchByteCount: highData.count
            )
        }

        return WIFixedSizeSolveOutcome(
            candidate: nil,
            smallestByteCount: min(highData.count, kneeData.count),
            dimensionSearchByteCount: min(highData.count, kneeData.count)
        )
    }

    private static func searchQuality(
        _ imageSource: WIImageSource,
        plan: WIExecutionPlan,
        renderedImage: CGImage?,
        maxBytes: Int,
        lowQuality: Double,
        highQuality: Double,
        lowData: Data,
        outputPixelSize: WIPixelSize,
        destinationFormat: ImageFormat,
        attemptCount: inout Int,
        maxEncodeAttempts: Int
    ) throws(WICompressError) -> WISolvedCompressionCandidate {
        var lowerBound = lowQuality
        var upperBound = highQuality
        var bestData = lowData
        var bestQuality = lowQuality

        for _ in 0..<6 {
            let quality = (lowerBound + upperBound) / 2
            let data = try encode(
                imageSource,
                plan: plan,
                renderedImage: renderedImage,
                quality: quality,
                attemptCount: &attemptCount,
                maxEncodeAttempts: maxEncodeAttempts
            )

            if data.count <= maxBytes {
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
            format: destinationFormat,
            quality: bestQuality
        )
    }

    private static func encode(
        _ imageSource: WIImageSource,
        plan: WIExecutionPlan,
        renderedImage: CGImage?,
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

        var qualityPlan = plan
        qualityPlan.quality = quality
        if let renderedImage {
            return try WIImageEncoder.encodeRendered(
                renderedImage,
                imageSource: imageSource,
                plan: qualityPlan
            )
        }

        return try WIImageEncoder.encode(
            imageSource,
            plan: qualityPlan
        )
    }

    private static func renderedImageIfNeeded(
        _ imageSource: WIImageSource,
        plan: WIExecutionPlan
    ) throws(WICompressError) -> CGImage? {
        guard case .render = plan.operation else {
            return nil
        }

        return try WIImageEncoder.render(
            imageSource,
            plan: plan
        )
    }

    private static func candidatePixelSize(
        sizing: WIResolvedCompressionSizing,
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

    private static func shouldReturnBestCandidate(
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
        return remainingAttempts < maxCandidateSearchEncodeAttempts
    }

    private static func minByteCount(
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

private struct WIFixedSizeSolveOutcome: Sendable, Equatable {
    var candidate: WISolvedCompressionCandidate?
    var smallestByteCount: Int?
    var dimensionSearchByteCount: Int?
}
