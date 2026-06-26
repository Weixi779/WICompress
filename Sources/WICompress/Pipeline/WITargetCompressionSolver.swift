//
//  WITargetCompressionSolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/24.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

enum WITargetCompressionSolver {
    static func compress(
        _ imageSource: WIImageSource,
        target: WICompressionTarget
    ) throws(WICompressError) -> Data {
        try validate(target)

        let referenceLongSide = resolvedReferenceLongSide(for: target, info: imageSource.info)
        let passthroughOptions = WICompressOptions(
            resize: .maxPixel(referenceLongSide),
            format: target.format,
            metadata: target.metadata,
            quality: .none
        )
        if imageSource.data.count <= target.maxBytes,
           WIWritePlanResolver.canReturnOriginalForSizeGuard(
               options: passthroughOptions,
               info: imageSource.info
           ) {
            return imageSource.data
        }

        let destinationPlan = try makePlan(
            target: target,
            info: imageSource.info,
            longSide: referenceLongSide,
            quality: nil
        )

        func encode(_ trial: WITargetByteBudgetOptimizer.EncodingTrial) throws(WICompressError) -> Data {
            try encodeCandidate(imageSource, target: target, trial: trial)
        }

        let outputData: Data
        switch destinationPlan.destinationFormat {
        case .jpeg, .heif:
            outputData = try WITargetByteBudgetOptimizer.solveLossy(
                maxBytes: target.maxBytes,
                initialLongSide: referenceLongSide,
                encode: encode
            )
        case .png:
            outputData = try WITargetByteBudgetOptimizer.solvePNG(
                maxBytes: target.maxBytes,
                initialLongSide: referenceLongSide,
                encode: encode
            )
        case .unknown:
            throw WICompressError.unsupportedDestinationFormat(.unknown)
        }

        guard outputData.count <= target.maxBytes else {
            throw WICompressError.targetBytesUnreachable(
                maxBytes: target.maxBytes,
                bestByteCount: outputData.count
            )
        }

        return outputData
    }

    private static func encodeCandidate(
        _ imageSource: WIImageSource,
        target: WICompressionTarget,
        trial: WITargetByteBudgetOptimizer.EncodingTrial
    ) throws(WICompressError) -> Data {
        let plan = try makePlan(
            target: target,
            info: imageSource.info,
            longSide: trial.longSide,
            quality: trial.quality
        )
        return try WIImageEncoder.encode(imageSource, plan: plan)
    }

    private static func resolvedReferenceLongSide(
        for target: WICompressionTarget,
        info: WIImageInfo
    ) -> Int {
        let sourceLongSide = info.displayLongSide
        guard let maxLongSide = target.maxLongSide else {
            return sourceLongSide
        }

        return min(sourceLongSide, maxLongSide)
    }

    private static func makePlan(
        target: WICompressionTarget,
        info: WIImageInfo,
        longSide: Int,
        quality: Double?
    ) throws(WICompressError) -> WIWritePlan {
        try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .maxPixel(max(longSide, 1)),
                format: target.format,
                metadata: target.metadata,
                quality: quality.map(WIQualityPolicy.compression) ?? .none
            ),
            info: info
        )
    }

    private static func validate(_ target: WICompressionTarget) throws(WICompressError) {
        guard target.maxBytes > 0 else {
            throw WICompressError.invalidCompressionTarget
        }

        if let maxLongSide = target.maxLongSide, maxLongSide <= 0 {
            throw WICompressError.invalidCompressionTarget
        }
    }

}
