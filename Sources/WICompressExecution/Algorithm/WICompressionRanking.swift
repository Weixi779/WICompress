//
//  WICompressionRanking.swift
//  WICompressExecution
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain
import WIImageIO

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
/// before ranking; this only balances pixel area against visual fidelity.
enum WICompressionRanking {
    static func bestCandidate(
        _ candidates: [WISolvedCompressionCandidate],
        referencePixelSize: WIPixelSize
    ) -> WISolvedCompressionCandidate {
        precondition(!candidates.isEmpty)

        return candidates.min { lhs, rhs in
            let lhsLoss = candidateLoss(
                lhs,
                referencePixelSize: referencePixelSize
            )
            let rhsLoss = candidateLoss(
                rhs,
                referencePixelSize: referencePixelSize
            )
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
        referencePixelSize: WIPixelSize
    ) -> Double {
        let referenceArea = max(pixelArea(referencePixelSize), 1)
        let candidateArea = max(candidate.pixelArea, 1)
        let areaScore = log2(candidateArea / referenceArea)
        let qualityPenalty = calibratedQualityPenalty(candidate.quality)
        let qKnee = WILossyQualityProfile(format: candidate.format).qKnee
        let kneePenalty = pow(max(0, qKnee - candidate.quality), 2)

        return abs(areaScore)
            + qualityPenalty
            + 2 * kneePenalty
    }

    private static func calibratedQualityPenalty(_ quality: Double) -> Double {
        pow(max(0, 1 - quality), 2) * 4
    }

    private static func pixelArea(_ size: WIPixelSize) -> Double {
        Double(size.width) * Double(size.height)
    }
}
