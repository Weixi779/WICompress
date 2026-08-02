//
//  TargetSearch.swift
//  WICompressExecution
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WICompressDomain
import WIImageDomain

struct PreparedTargetEncoding {
    let pixelSize: WIPixelSize
    let encode: (_ quality: Double?) throws(WICompressError) -> Data
}

struct LossyTargetSearch {
    typealias Prepare = (
        _ pixelSize: WIPixelSize,
        _ initialQuality: Double
    ) throws(WICompressError) -> PreparedTargetEncoding

    private static let candidateSearchAttemptCount = 8

    let maxBytes: Int
    let format: ImageFormat
    let basePixelSize: WIPixelSize
    let maxEncodeAttempts: Int
    let prepare: Prepare

    private var attemptCount = 0

    init(
        maxBytes: Int,
        format: ImageFormat,
        basePixelSize: WIPixelSize,
        maxEncodeAttempts: Int,
        prepare: @escaping Prepare
    ) {
        self.maxBytes = maxBytes
        self.format = format
        self.basePixelSize = basePixelSize
        self.maxEncodeAttempts = maxEncodeAttempts
        self.prepare = prepare
    }

    mutating func run() throws(WICompressError) -> Data {
        let profile = LossyQualityProfile(format: format)
        var currentLongSide = max(basePixelSize.width, basePixelSize.height)
        var longSideOverride: Int?
        var highQuality = profile.high
        var smallestByteCount: Int?
        var candidates: [TargetCandidate] = []

        while true {
            if shouldReturnBestCandidate(candidates) {
                return bestCandidate(in: candidates).data
            }

            let pixelSize = candidatePixelSize(
                base: basePixelSize,
                maxLongSide: longSideOverride
            )
            let encoding = try prepare(pixelSize, highQuality)
            let outcome: FixedSizeOutcome
            do {
                outcome = try searchFixedSize(
                    encoding,
                    profile: profile,
                    highQuality: highQuality
                )
            } catch WICompressError.resourceLimitExceeded {
                guard candidates.isEmpty else {
                    return bestCandidate(in: candidates).data
                }
                throw .resourceLimitExceeded(attemptCount: attemptCount)
            }

            if let candidate = outcome.candidate {
                candidates.append(candidate)
                if candidate.quality >= highQuality {
                    return bestCandidate(in: candidates).data
                }
            }

            smallestByteCount = minimumByteCount(
                smallestByteCount,
                outcome.smallestByteCount
            )
            guard
                let estimateByteCount = outcome.dimensionSearchByteCount
                    ?? outcome.smallestByteCount,
                let nextLongSide = TargetSizeEstimation.nextLongSide(
                    current: currentLongSide,
                    encodedBytes: estimateByteCount,
                    maxBytes: maxBytes,
                    format: format
                )
            else {
                guard candidates.isEmpty else {
                    return bestCandidate(in: candidates).data
                }
                throw .targetUnsatisfiable(smallestByteCount: smallestByteCount)
            }

            currentLongSide = nextLongSide
            longSideOverride = nextLongSide
            highQuality = profile.anchor
        }
    }

    private mutating func searchFixedSize(
        _ encoding: PreparedTargetEncoding,
        profile: LossyQualityProfile,
        highQuality: Double
    ) throws(WICompressError) -> FixedSizeOutcome {
        let highData = try encode(encoding, quality: highQuality)
        if highData.count <= maxBytes {
            return FixedSizeOutcome(
                candidate: TargetCandidate(
                    data: highData,
                    pixelSize: encoding.pixelSize,
                    format: format,
                    quality: highQuality
                ),
                smallestByteCount: highData.count,
                dimensionSearchByteCount: nil
            )
        }

        let kneeData = try encode(encoding, quality: profile.knee)
        if kneeData.count <= maxBytes {
            return FixedSizeOutcome(
                candidate: try searchQuality(
                    encoding,
                    lowQuality: profile.knee,
                    highQuality: highQuality,
                    lowData: kneeData
                ),
                smallestByteCount: kneeData.count,
                dimensionSearchByteCount: highData.count
            )
        }

        let smallestByteCount = min(highData.count, kneeData.count)
        return FixedSizeOutcome(
            candidate: nil,
            smallestByteCount: smallestByteCount,
            dimensionSearchByteCount: smallestByteCount
        )
    }

    private mutating func searchQuality(
        _ encoding: PreparedTargetEncoding,
        lowQuality: Double,
        highQuality: Double,
        lowData: Data
    ) throws(WICompressError) -> TargetCandidate {
        var lowerBound = lowQuality
        var upperBound = highQuality
        var bestData = lowData
        var bestQuality = lowQuality

        for _ in 0..<6 {
            let quality = (lowerBound + upperBound) / 2
            let data = try encode(encoding, quality: quality)
            if data.count <= maxBytes {
                lowerBound = quality
                bestData = data
                bestQuality = quality
            } else {
                upperBound = quality
            }
        }

        return TargetCandidate(
            data: bestData,
            pixelSize: encoding.pixelSize,
            format: format,
            quality: bestQuality
        )
    }

    private mutating func encode(
        _ encoding: PreparedTargetEncoding,
        quality: Double
    ) throws(WICompressError) -> Data {
        guard attemptCount < maxEncodeAttempts else {
            throw .resourceLimitExceeded(attemptCount: attemptCount)
        }
        attemptCount += 1
        return try encoding.encode(quality)
    }

    private func shouldReturnBestCandidate(_ candidates: [TargetCandidate]) -> Bool {
        guard !candidates.isEmpty else {
            return false
        }
        let remainingAttempts = max(maxEncodeAttempts - attemptCount, 0)
        return remainingAttempts < Self.candidateSearchAttemptCount
    }

    private func bestCandidate(in candidates: [TargetCandidate]) -> TargetCandidate {
        TargetCandidateRanking.best(
            from: candidates,
            referencePixelSize: basePixelSize
        )
    }
}

struct PNGTargetSearch {
    typealias Prepare = (
        _ pixelSize: WIPixelSize
    ) throws(WICompressError) -> PreparedTargetEncoding

    let maxBytes: Int
    let basePixelSize: WIPixelSize
    let maxEncodeAttempts: Int
    let prepare: Prepare

    private var attemptCount = 0

    init(
        maxBytes: Int,
        basePixelSize: WIPixelSize,
        maxEncodeAttempts: Int,
        prepare: @escaping Prepare
    ) {
        self.maxBytes = maxBytes
        self.basePixelSize = basePixelSize
        self.maxEncodeAttempts = maxEncodeAttempts
        self.prepare = prepare
    }

    mutating func run() throws(WICompressError) -> Data {
        var currentLongSide = max(basePixelSize.width, basePixelSize.height)
        var longSideOverride: Int?
        var smallestByteCount: Int?

        while true {
            let pixelSize = candidatePixelSize(
                base: basePixelSize,
                maxLongSide: longSideOverride
            )
            let encoding = try prepare(pixelSize)
            let data = try encode(encoding)
            if data.count <= maxBytes {
                return data
            }

            smallestByteCount = minimumByteCount(smallestByteCount, data.count)
            guard let nextLongSide = TargetSizeEstimation.nextLongSide(
                current: currentLongSide,
                encodedBytes: data.count,
                maxBytes: maxBytes,
                format: .png
            ) else {
                throw .targetUnsatisfiable(smallestByteCount: smallestByteCount)
            }

            currentLongSide = nextLongSide
            longSideOverride = nextLongSide
        }
    }

    private mutating func encode(
        _ encoding: PreparedTargetEncoding
    ) throws(WICompressError) -> Data {
        guard attemptCount < maxEncodeAttempts else {
            throw .resourceLimitExceeded(attemptCount: attemptCount)
        }
        attemptCount += 1
        return try encoding.encode(nil)
    }
}

struct LossyQualityProfile: Sendable, Equatable {
    let high: Double
    let anchor: Double
    let knee: Double

    init(format: ImageFormat) {
        switch format {
        case .jpeg:
            self.init(high: 0.82, anchor: 0.72, knee: 0.45)
        case .heif:
            self.init(high: 0.78, anchor: 0.68, knee: 0.42)
        case .png, .unknown:
            self.init(high: 0, anchor: 0, knee: 0)
        }
    }

    private init(high: Double, anchor: Double, knee: Double) {
        self.high = high
        self.anchor = anchor
        self.knee = knee
    }
}

private struct FixedSizeOutcome {
    let candidate: TargetCandidate?
    let smallestByteCount: Int?
    let dimensionSearchByteCount: Int?
}

private func candidatePixelSize(
    base: WIPixelSize,
    maxLongSide: Int?
) -> WIPixelSize {
    guard let maxLongSide else {
        return base
    }
    return TargetSizeEstimation.scaledPixelSize(
        source: base,
        maxLongSide: maxLongSide
    )
}

private func minimumByteCount(_ lhs: Int?, _ rhs: Int?) -> Int? {
    switch (lhs, rhs) {
    case (.some(let lhs), .some(let rhs)):
        min(lhs, rhs)
    case (.some(let lhs), .none):
        lhs
    case (.none, .some(let rhs)):
        rhs
    case (.none, .none):
        nil
    }
}
