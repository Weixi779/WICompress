//
//  WITargetCompressionSolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/24.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

enum WITargetCompressionSolver {
    private enum LossyProfile {
        static let high = 0.82
        static let anchor = 0.72
        static let knee = 0.45
        static let emergency = 0.25
    }

    private static let sizePredictionSafety = 0.88
    private static let maximumLossySizeAttempts = 8
    private static let maximumPNGSizeAttempts = 12
    private static let maximumQualitySearchAttempts = 6

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

        let destinationProbe = try makePlan(
            target: target,
            info: imageSource.info,
            longSide: referenceLongSide,
            quality: LossyProfile.high
        )

        let outputData: Data
        switch destinationProbe.destinationFormat {
        case .jpeg, .heif:
            outputData = try solveLossy(
                imageSource,
                target: target,
                initialLongSide: referenceLongSide
            )
        case .png:
            outputData = try solvePNG(
                imageSource,
                target: target,
                initialLongSide: referenceLongSide
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

    private static func solveLossy(
        _ imageSource: WIImageSource,
        target: WICompressionTarget,
        initialLongSide: Int
    ) throws(WICompressError) -> Data {
        var search = WITargetSearch()
        var currentLongSide = max(initialLongSide, 1)

        for _ in 0..<maximumLossySizeAttempts {
            let high = try encodeCandidate(
                imageSource,
                target: target,
                longSide: currentLongSide,
                quality: LossyProfile.high
            )
            search.record(high, maxBytes: target.maxBytes)
            if high.byteCount <= target.maxBytes {
                return bestCandidate(in: search).data
            }

            let knee = try encodeCandidate(
                imageSource,
                target: target,
                longSide: currentLongSide,
                quality: LossyProfile.knee
            )
            search.record(knee, maxBytes: target.maxBytes)

            if knee.byteCount <= target.maxBytes {
                let bestAtCurrentSize = try searchHighestFeasibleQuality(
                    imageSource,
                    target: target,
                    longSide: currentLongSide,
                    knownFeasible: knee,
                    search: &search
                )

                if !bestAtCurrentSize.hitQualityKnee {
                    return bestCandidate(in: search).data
                }

                let nextLongSide = predictedNextLongSide(
                    currentLongSide: currentLongSide,
                    encodedBytes: knee.byteCount,
                    maxBytes: target.maxBytes
                )
                if nextLongSide < currentLongSide {
                    let anchorProbe = try encodeCandidate(
                        imageSource,
                        target: target,
                        longSide: nextLongSide,
                        quality: LossyProfile.anchor
                    )
                    search.record(anchorProbe, maxBytes: target.maxBytes)
                }

                return bestCandidate(in: search).data
            }

            let nextLongSide = predictedNextLongSide(
                currentLongSide: currentLongSide,
                encodedBytes: knee.byteCount,
                maxBytes: target.maxBytes
            )
            guard nextLongSide < currentLongSide else {
                break
            }

            currentLongSide = nextLongSide
        }

        var emergencyLongSide = min(currentLongSide, initialLongSide)
        for _ in 0..<maximumLossySizeAttempts where emergencyLongSide >= 1 {
            let emergency = try encodeCandidate(
                imageSource,
                target: target,
                longSide: emergencyLongSide,
                quality: LossyProfile.emergency
            )
            search.record(emergency, maxBytes: target.maxBytes)
            if emergency.byteCount <= target.maxBytes {
                return bestCandidate(in: search).data
            }

            let nextLongSide = predictedNextLongSide(
                currentLongSide: emergencyLongSide,
                encodedBytes: emergency.byteCount,
                maxBytes: target.maxBytes
            )
            guard nextLongSide < emergencyLongSide else {
                break
            }

            emergencyLongSide = nextLongSide
        }

        throw WICompressError.targetBytesUnreachable(
            maxBytes: target.maxBytes,
            bestByteCount: search.smallestByteCount
        )
    }

    private static func solvePNG(
        _ imageSource: WIImageSource,
        target: WICompressionTarget,
        initialLongSide: Int
    ) throws(WICompressError) -> Data {
        var search = WITargetSearch()
        var currentLongSide = max(initialLongSide, 1)

        for _ in 0..<maximumPNGSizeAttempts {
            let candidate = try encodeCandidate(
                imageSource,
                target: target,
                longSide: currentLongSide,
                quality: nil
            )
            search.record(candidate, maxBytes: target.maxBytes)
            if candidate.byteCount <= target.maxBytes {
                return bestCandidate(in: search).data
            }

            let nextLongSide = predictedNextLongSide(
                currentLongSide: currentLongSide,
                encodedBytes: candidate.byteCount,
                maxBytes: target.maxBytes
            )
            guard nextLongSide < currentLongSide else {
                break
            }

            currentLongSide = nextLongSide
        }

        throw WICompressError.targetBytesUnreachable(
            maxBytes: target.maxBytes,
            bestByteCount: search.smallestByteCount
        )
    }

    private static func searchHighestFeasibleQuality(
        _ imageSource: WIImageSource,
        target: WICompressionTarget,
        longSide: Int,
        knownFeasible: WITargetCandidate,
        search: inout WITargetSearch
    ) throws(WICompressError) -> WITargetCandidate {
        var best = knownFeasible
        var lowQuality = LossyProfile.knee
        var highQuality = LossyProfile.high
        var encodedQualityKeys: Set<Int> = [
            qualityKey(LossyProfile.knee),
            qualityKey(LossyProfile.high)
        ]

        for _ in 0..<maximumQualitySearchAttempts {
            let quality = (lowQuality + highQuality) / 2.0
            let key = qualityKey(quality)
            guard !encodedQualityKeys.contains(key) else {
                break
            }

            encodedQualityKeys.insert(key)
            let candidate = try encodeCandidate(
                imageSource,
                target: target,
                longSide: longSide,
                quality: quality
            )
            search.record(candidate, maxBytes: target.maxBytes)

            if candidate.byteCount <= target.maxBytes {
                best = candidate
                lowQuality = quality
            } else {
                highQuality = quality
            }
        }

        return best
    }

    private static func encodeCandidate(
        _ imageSource: WIImageSource,
        target: WICompressionTarget,
        longSide: Int,
        quality: Double?
    ) throws(WICompressError) -> WITargetCandidate {
        let plan = try makePlan(
            target: target,
            info: imageSource.info,
            longSide: longSide,
            quality: quality
        )
        let data = try WIImageEncoder.encode(imageSource, plan: plan)
        return WITargetCandidate(
            data: data,
            byteCount: data.count,
            longSide: longSide,
            quality: quality,
            hitQualityKnee: quality.map { $0 <= LossyProfile.knee + 0.05 } ?? false
        )
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

    private static func bestCandidate(in search: WITargetSearch) -> WITargetCandidate {
        search.candidates.sorted { lhs, rhs in
            if lhs.hitQualityKnee != rhs.hitQualityKnee {
                return !lhs.hitQualityKnee && rhs.hitQualityKnee
            }

            if lhs.longSide != rhs.longSide {
                return lhs.longSide > rhs.longSide
            }

            let lhsQuality = lhs.quality ?? 1.0
            let rhsQuality = rhs.quality ?? 1.0
            if lhsQuality != rhsQuality {
                return lhsQuality > rhsQuality
            }

            return lhs.byteCount < rhs.byteCount
        }[0]
    }

    private static func predictedNextLongSide(
        currentLongSide: Int,
        encodedBytes: Int,
        maxBytes: Int
    ) -> Int {
        guard encodedBytes > 0, maxBytes > 0 else {
            return max(currentLongSide - 1, 1)
        }

        let ratio = sqrt(Double(maxBytes) / Double(encodedBytes)) * sizePredictionSafety
        let predicted = Int(floor(Double(currentLongSide) * ratio))
        let clamped = min(max(predicted, 1), max(currentLongSide - 1, 1))
        return evenLongSideIfPossible(clamped)
    }

    private static func evenLongSideIfPossible(_ longSide: Int) -> Int {
        guard longSide > 2 else {
            return longSide
        }

        return longSide.isMultiple(of: 2) ? longSide : longSide - 1
    }

    private static func resolvedReferenceLongSide(
        for target: WICompressionTarget,
        info: WIImageInfo
    ) -> Int {
        let displaySize = displayDimensions(for: info)
        let sourceLongSide = max(displaySize.width, displaySize.height)
        guard let maxLongSide = target.maxLongSide else {
            return sourceLongSide
        }

        return min(sourceLongSide, maxLongSide)
    }

    private static func displayDimensions(for info: WIImageInfo) -> (width: Int, height: Int) {
        switch info.orientation {
        case 5, 6, 7, 8:
            return (info.pixelHeight, info.pixelWidth)
        default:
            return (info.pixelWidth, info.pixelHeight)
        }
    }

    private static func validate(_ target: WICompressionTarget) throws(WICompressError) {
        guard target.maxBytes > 0 else {
            throw WICompressError.invalidCompressionTarget
        }

        if let maxLongSide = target.maxLongSide, maxLongSide <= 0 {
            throw WICompressError.invalidCompressionTarget
        }
    }

    private static func qualityKey(_ quality: Double) -> Int {
        Int((quality * 1_000).rounded())
    }
}

private struct WITargetCandidate {
    var data: Data
    var byteCount: Int
    var longSide: Int
    var quality: Double?
    var hitQualityKnee: Bool
}

private struct WITargetSearch {
    var candidates: [WITargetCandidate] = []
    var smallestByteCount: Int?

    mutating func record(_ candidate: WITargetCandidate, maxBytes: Int) {
        if let currentSmallest = smallestByteCount {
            smallestByteCount = min(currentSmallest, candidate.byteCount)
        } else {
            smallestByteCount = candidate.byteCount
        }

        guard candidate.byteCount <= maxBytes else {
            return
        }

        candidates.append(candidate)
    }
}
