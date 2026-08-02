//
//  TargetCandidate.swift
//  WICompressExecution
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

/// A feasible encoded result found during a lossy byte-budget search.
struct TargetCandidate: Sendable, Equatable {
    let data: Data
    let pixelSize: WIPixelSize
    let format: ImageFormat
    let quality: Double

    var pixelArea: Double {
        Double(pixelSize.width) * Double(pixelSize.height)
    }
}

/// Selects one deterministic balance between spatial resolution and quality.
enum TargetCandidateRanking {
    static func best(
        from candidates: [TargetCandidate],
        referencePixelSize: WIPixelSize
    ) -> TargetCandidate {
        precondition(!candidates.isEmpty)

        return candidates.min { lhs, rhs in
            let lhsLoss = candidateLoss(lhs, referencePixelSize: referencePixelSize)
            let rhsLoss = candidateLoss(rhs, referencePixelSize: referencePixelSize)
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
        _ candidate: TargetCandidate,
        referencePixelSize: WIPixelSize
    ) -> Double {
        let referenceArea = max(pixelArea(referencePixelSize), 1)
        let candidateArea = max(candidate.pixelArea, 1)
        let areaScore = log2(candidateArea / referenceArea)
        let qualityPenalty = pow(max(0, 1 - candidate.quality), 2) * 4
        let knee = LossyQualityProfile(format: candidate.format).knee
        let kneePenalty = pow(max(0, knee - candidate.quality), 2)

        return abs(areaScore) + qualityPenalty + 2 * kneePenalty
    }

    private static func pixelArea(_ size: WIPixelSize) -> Double {
        Double(size.width) * Double(size.height)
    }
}
