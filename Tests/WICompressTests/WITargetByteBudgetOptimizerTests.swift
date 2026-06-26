//
//  WITargetByteBudgetOptimizerTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/6/25.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import Testing
@testable import WICompress

@Suite("WITargetByteBudgetOptimizer", .tags(.compression, .edgeCase))
struct WITargetByteBudgetOptimizerTests {
    @Test("Lossy search returns the high profile when it fits")
    func lossyReturnsHighProfileWhenItFits() throws {
        var trials: [WITargetByteBudgetOptimizer.EncodingTrial] = []

        let output = try WITargetByteBudgetOptimizer.solveLossy(
            maxBytes: 100_000,
            initialLongSide: 1_000
        ) { trial in
            trials.append(trial)
            return Self.data(byteCount: 90_000, marker: Self.qualityPercent(trial.quality))
        }

        #expect(output.count == 90_000)
        #expect(trials.count == 1)
        let outputMarker = try #require(output.first)
        let firstTrial = try #require(trials.first)
        #expect(outputMarker == 82)
        #expect(firstTrial.longSide == 1_000)
        #expect(Self.qualityPercent(firstTrial.quality) == 82)
    }

    @Test("Lossy search keeps the current size when a better quality fits")
    func lossySearchesHighestFeasibleQualityAtCurrentSize() throws {
        var trials: [WITargetByteBudgetOptimizer.EncodingTrial] = []

        let output = try WITargetByteBudgetOptimizer.solveLossy(
            maxBytes: 60_000,
            initialLongSide: 1_000
        ) { trial in
            trials.append(trial)
            let quality = trial.quality ?? 1.0
            return Self.data(
                byteCount: Int((quality * 100_000).rounded()),
                marker: Self.qualityPercent(trial.quality)
            )
        }

        #expect(output.count <= 60_000)
        let outputMarker = try #require(output.first)
        #expect(outputMarker > 45)
        #expect(trials.allSatisfy { $0.longSide == 1_000 })
    }

    @Test("Lossy search tries a smaller anchor when only the knee fits")
    func lossySearchesSmallerAnchorAfterQualityKnee() throws {
        var trials: [WITargetByteBudgetOptimizer.EncodingTrial] = []

        let output = try WITargetByteBudgetOptimizer.solveLossy(
            maxBytes: 100_000,
            initialLongSide: 1_000
        ) { trial in
            trials.append(trial)
            let qualityPercent = Self.qualityPercent(trial.quality)
            if trial.longSide < 1_000, qualityPercent == 72 {
                return Self.data(byteCount: 80_000, marker: qualityPercent)
            }
            if qualityPercent == 45 {
                return Self.data(byteCount: 90_000, marker: qualityPercent)
            }
            return Self.data(byteCount: 120_000, marker: qualityPercent)
        }

        let anchorTrial = try #require(
            trials.first { $0.longSide < 1_000 && Self.qualityPercent($0.quality) == 72 }
        )
        #expect(output.count == 80_000)
        let outputMarker = try #require(output.first)
        #expect(outputMarker == 72)
        #expect(anchorTrial.longSide < 1_000)
    }

    @Test("PNG search reduces long side using byte-ratio prediction")
    func pngSearchReducesLongSideByPrediction() throws {
        var trials: [WITargetByteBudgetOptimizer.EncodingTrial] = []

        let output = try WITargetByteBudgetOptimizer.solvePNG(
            maxBytes: 100_000,
            initialLongSide: 1_000
        ) { trial in
            trials.append(trial)
            switch trial.longSide {
            case 1_000:
                return Self.data(byteCount: 400_000, marker: 1)
            case 440:
                return Self.data(byteCount: 80_000, marker: 2)
            default:
                return Self.data(byteCount: 300_000, marker: 3)
            }
        }

        #expect(output.count == 80_000)
        let outputMarker = try #require(output.first)
        #expect(outputMarker == 2)
        #expect(trials.map(\.longSide) == [1_000, 440])
        #expect(trials.allSatisfy { $0.quality == nil })
    }

    @Test("PNG search reports the smallest encoded byte count when unreachable")
    func pngSearchReportsBestByteCountWhenUnreachable() throws {
        #expect(throws: WICompressError.targetBytesUnreachable(maxBytes: 10, bestByteCount: 100)) {
            _ = try WITargetByteBudgetOptimizer.solvePNG(
                maxBytes: 10,
                initialLongSide: 100
            ) { trial in
                Self.data(byteCount: max(trial.longSide * 100, 1), marker: 0)
            }
        }
    }

    private static func data(byteCount: Int, marker: Int) -> Data {
        Data(repeating: UInt8(clamping: marker), count: max(byteCount, 1))
    }

    private static func qualityPercent(_ quality: Double?) -> Int {
        Int(((quality ?? 1.0) * 100).rounded())
    }
}
