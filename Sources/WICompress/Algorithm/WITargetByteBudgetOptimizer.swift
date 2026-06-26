//
//  WITargetByteBudgetOptimizer.swift
//  WICompress
//
//  Created by weixi on 2026/6/25.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Chooses encode dimensions and quality that fit a target byte budget.
enum WITargetByteBudgetOptimizer {
    /// One encode attempt requested from the ImageIO pipeline.
    struct EncodingTrial: Sendable, Equatable {
        /// Target display long side in pixels for this attempt.
        var longSide: Int
        /// Lossy quality for JPEG/HEIC attempts; nil for PNG.
        var quality: Double?
    }

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

    /// Searches lossy formats by trying quality first, then reducing dimensions when needed.
    static func solveLossy(
        maxBytes: Int,
        initialLongSide: Int,
        encode: (EncodingTrial) throws(WICompressError) -> Data
    ) throws(WICompressError) -> Data {
        var search = Search()
        var currentLongSide = max(initialLongSide, 1)

        for _ in 0..<maximumLossySizeAttempts {
            let high = try encodeCandidate(
                longSide: currentLongSide,
                quality: LossyProfile.high,
                encode: encode
            )
            search.record(high, maxBytes: maxBytes)
            if high.byteCount <= maxBytes {
                return bestCandidate(in: search).data
            }

            let knee = try encodeCandidate(
                longSide: currentLongSide,
                quality: LossyProfile.knee,
                encode: encode
            )
            search.record(knee, maxBytes: maxBytes)

            if knee.byteCount <= maxBytes {
                let bestAtCurrentSize = try searchHighestFeasibleQuality(
                    longSide: currentLongSide,
                    maxBytes: maxBytes,
                    knownFeasible: knee,
                    search: &search,
                    encode: encode
                )

                if !bestAtCurrentSize.hitQualityKnee {
                    return bestCandidate(in: search).data
                }

                let nextLongSide = predictedNextLongSide(
                    currentLongSide: currentLongSide,
                    encodedBytes: knee.byteCount,
                    maxBytes: maxBytes
                )
                if nextLongSide < currentLongSide {
                    let anchorCandidate = try encodeCandidate(
                        longSide: nextLongSide,
                        quality: LossyProfile.anchor,
                        encode: encode
                    )
                    search.record(anchorCandidate, maxBytes: maxBytes)
                }

                return bestCandidate(in: search).data
            }

            let nextLongSide = predictedNextLongSide(
                currentLongSide: currentLongSide,
                encodedBytes: knee.byteCount,
                maxBytes: maxBytes
            )
            guard nextLongSide < currentLongSide else {
                break
            }

            currentLongSide = nextLongSide
        }

        var emergencyLongSide = min(currentLongSide, initialLongSide)
        for _ in 0..<maximumLossySizeAttempts where emergencyLongSide >= 1 {
            let emergency = try encodeCandidate(
                longSide: emergencyLongSide,
                quality: LossyProfile.emergency,
                encode: encode
            )
            search.record(emergency, maxBytes: maxBytes)
            if emergency.byteCount <= maxBytes {
                return bestCandidate(in: search).data
            }

            let nextLongSide = predictedNextLongSide(
                currentLongSide: emergencyLongSide,
                encodedBytes: emergency.byteCount,
                maxBytes: maxBytes
            )
            guard nextLongSide < emergencyLongSide else {
                break
            }

            emergencyLongSide = nextLongSide
        }

        throw WICompressError.targetBytesUnreachable(
            maxBytes: maxBytes,
            bestByteCount: search.smallestByteCount
        )
    }

    /// Searches PNG output by reducing dimensions, since PNG has no lossy quality knob.
    static func solvePNG(
        maxBytes: Int,
        initialLongSide: Int,
        encode: (EncodingTrial) throws(WICompressError) -> Data
    ) throws(WICompressError) -> Data {
        var search = Search()
        var currentLongSide = max(initialLongSide, 1)

        for _ in 0..<maximumPNGSizeAttempts {
            let candidate = try encodeCandidate(
                longSide: currentLongSide,
                quality: nil,
                encode: encode
            )
            search.record(candidate, maxBytes: maxBytes)
            if candidate.byteCount <= maxBytes {
                return bestCandidate(in: search).data
            }

            let nextLongSide = predictedNextLongSide(
                currentLongSide: currentLongSide,
                encodedBytes: candidate.byteCount,
                maxBytes: maxBytes
            )
            guard nextLongSide < currentLongSide else {
                break
            }

            currentLongSide = nextLongSide
        }

        throw WICompressError.targetBytesUnreachable(
            maxBytes: maxBytes,
            bestByteCount: search.smallestByteCount
        )
    }

    private static func searchHighestFeasibleQuality(
        longSide: Int,
        maxBytes: Int,
        knownFeasible: Candidate,
        search: inout Search,
        encode: (EncodingTrial) throws(WICompressError) -> Data
    ) throws(WICompressError) -> Candidate {
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
                longSide: longSide,
                quality: quality,
                encode: encode
            )
            search.record(candidate, maxBytes: maxBytes)

            if candidate.byteCount <= maxBytes {
                best = candidate
                lowQuality = quality
            } else {
                highQuality = quality
            }
        }

        return best
    }

    private static func encodeCandidate(
        longSide: Int,
        quality: Double?,
        encode: (EncodingTrial) throws(WICompressError) -> Data
    ) throws(WICompressError) -> Candidate {
        let data = try encode(
            EncodingTrial(
                longSide: longSide,
                quality: quality
            )
        )
        return Candidate(
            data: data,
            byteCount: data.count,
            longSide: longSide,
            quality: quality,
            hitQualityKnee: quality.map { $0 <= LossyProfile.knee + 0.05 } ?? false
        )
    }

    private static func bestCandidate(in search: Search) -> Candidate {
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

    private static func qualityKey(_ quality: Double) -> Int {
        Int((quality * 1_000).rounded())
    }
}

private struct Candidate {
    var data: Data
    var byteCount: Int
    var longSide: Int
    var quality: Double?
    var hitQualityKnee: Bool
}

private struct Search {
    var candidates: [Candidate] = []
    var smallestByteCount: Int?

    mutating func record(_ candidate: Candidate, maxBytes: Int) {
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
