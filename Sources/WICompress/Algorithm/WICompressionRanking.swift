//
//  WICompressionRanking.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// A feasible encoded result collected during the target byte-budget search.
struct WISolvedCompressionCandidate: Sendable, Equatable {
    var data: Data
    var pixelSize: WIPixelSize
    var format: WIImageFormat
    var quality: Double

    var pixelArea: Double {
        Double(pixelSize.width) * Double(pixelSize.height)
    }
}

/// Deterministic candidate ranking. Hard constraints are filtered by the solver
/// before ranking; this only orders the survivors by a preference-weighted loss
/// that balances pixel area against visual fidelity.
enum WICompressionRanking {
    static func bestCandidate(
        _ candidates: [WISolvedCompressionCandidate],
        preference: WICompressionPreference,
        referencePixelSize: WIPixelSize
    ) -> WISolvedCompressionCandidate {
        precondition(!candidates.isEmpty)

        return candidates.min { lhs, rhs in
            let lhsLoss = candidateLoss(lhs, preference: preference, referencePixelSize: referencePixelSize)
            let rhsLoss = candidateLoss(rhs, preference: preference, referencePixelSize: referencePixelSize)
            if abs(lhsLoss - rhsLoss) > 0.000_001 {
                return lhsLoss < rhsLoss
            }

            if lhs.quality != rhs.quality {
                return lhs.quality > rhs.quality
            }

            if lhs.pixelArea != rhs.pixelArea {
                return lhs.pixelArea > rhs.pixelArea
            }

            return lhs.data.count < rhs.data.count
        }!
    }

    private static func candidateLoss(
        _ candidate: WISolvedCompressionCandidate,
        preference: WICompressionPreference,
        referencePixelSize: WIPixelSize
    ) -> Double {
        let weights = WICandidateScoreWeights(preference: preference)
        let referenceArea = max(pixelArea(referencePixelSize), 1)
        let candidateArea = max(candidate.pixelArea, 1)
        let areaScore = log2(candidateArea / referenceArea)
        let qualityPenalty = calibratedQualityPenalty(candidate.quality)
        let qKnee = WILossyQualityProfile(format: candidate.format).qKnee
        let kneePenalty = pow(max(0, qKnee - candidate.quality), 2)

        return weights.area * abs(areaScore)
            + weights.quality * qualityPenalty
            + weights.knee * kneePenalty
    }

    private static func calibratedQualityPenalty(_ quality: Double) -> Double {
        pow(max(0, 1 - quality), 2) * 4
    }

    private static func pixelArea(_ size: WIPixelSize) -> Double {
        Double(size.width) * Double(size.height)
    }
}

private struct WICandidateScoreWeights: Sendable, Equatable {
    var area: Double
    var quality: Double
    var knee: Double

    init(preference: WICompressionPreference) {
        switch preference {
        case .balanced:
            self.init(area: 1.0, quality: 1.0, knee: 2.0)
        case .preserveResolution:
            self.init(area: 1.3, quality: 0.8, knee: 1.5)
        case .preserveFidelity:
            self.init(area: 0.8, quality: 1.3, knee: 2.5)
        }
    }

    private init(area: Double, quality: Double, knee: Double) {
        self.area = area
        self.quality = quality
        self.knee = knee
    }
}
