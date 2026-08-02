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
    let encode: (_ quality: Double?) throws -> Data
}

struct LossyTargetSearch {
    typealias Prepare = (
        _ pixelSize: WIPixelSize,
        _ initialQuality: Double
    ) throws -> PreparedTargetEncoding
    typealias CheckCancellation = () throws(CancellationError) -> Void

    private static let candidateSearchAttemptCount = 8

    let maxBytes: Int
    let format: ImageFormat
    let basePixelSize: WIPixelSize
    let maxEncodeAttempts: Int
    let checkCancellation: CheckCancellation
    let prepare: Prepare

    private var attemptCount = 0

    init(
        maxBytes: Int,
        format: ImageFormat,
        basePixelSize: WIPixelSize,
        maxEncodeAttempts: Int,
        checkCancellation: @escaping CheckCancellation = {},
        prepare: @escaping Prepare
    ) {
        self.maxBytes = maxBytes
        self.format = format
        self.basePixelSize = basePixelSize
        self.maxEncodeAttempts = maxEncodeAttempts
        self.checkCancellation = checkCancellation
        self.prepare = prepare
    }

    mutating func run() throws -> Data {
        let profile = LossyQualityProfile(format: format)
        var currentLongSide = max(basePixelSize.width, basePixelSize.height)
        var longSideOverride: Int?
        var highQuality = profile.high
        var smallestByteCount: Int?
        var candidates: [TargetCandidate] = []

        while true {
            try checkCancellation()
            if shouldReturnBestCandidate(candidates) {
                return bestCandidate(in: candidates).data
            }

            let pixelSize = candidatePixelSize(
                base: basePixelSize,
                maxLongSide: longSideOverride
            )
            try checkCancellation()
            let encoding = try prepare(pixelSize, highQuality)
            try checkCancellation()
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
                throw WICompressError.resourceLimitExceeded(
                    attemptCount: attemptCount
                )
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
                throw WICompressError.targetUnsatisfiable(
                    smallestByteCount: smallestByteCount
                )
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
    ) throws -> FixedSizeOutcome {
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
    ) throws -> TargetCandidate {
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
    ) throws -> Data {
        try checkCancellation()
        guard attemptCount < maxEncodeAttempts else {
            throw WICompressError.resourceLimitExceeded(
                attemptCount: attemptCount
            )
        }
        attemptCount += 1
        let data = try encoding.encode(quality)
        try checkCancellation()
        return data
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
    ) throws -> PreparedTargetEncoding
    typealias CheckCancellation = () throws(CancellationError) -> Void

    let maxBytes: Int
    let basePixelSize: WIPixelSize
    let maxEncodeAttempts: Int
    let checkCancellation: CheckCancellation
    let prepare: Prepare

    private var attemptCount = 0

    init(
        maxBytes: Int,
        basePixelSize: WIPixelSize,
        maxEncodeAttempts: Int,
        checkCancellation: @escaping CheckCancellation = {},
        prepare: @escaping Prepare
    ) {
        self.maxBytes = maxBytes
        self.basePixelSize = basePixelSize
        self.maxEncodeAttempts = maxEncodeAttempts
        self.checkCancellation = checkCancellation
        self.prepare = prepare
    }

    mutating func run() throws -> Data {
        var currentLongSide = max(basePixelSize.width, basePixelSize.height)
        var longSideOverride: Int?
        var smallestByteCount: Int?

        while true {
            try checkCancellation()
            let pixelSize = candidatePixelSize(
                base: basePixelSize,
                maxLongSide: longSideOverride
            )
            try checkCancellation()
            let encoding = try prepare(pixelSize)
            try checkCancellation()
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
                throw WICompressError.targetUnsatisfiable(
                    smallestByteCount: smallestByteCount
                )
            }

            currentLongSide = nextLongSide
            longSideOverride = nextLongSide
        }
    }

    private mutating func encode(
        _ encoding: PreparedTargetEncoding
    ) throws -> Data {
        try checkCancellation()
        guard attemptCount < maxEncodeAttempts else {
            throw WICompressError.resourceLimitExceeded(
                attemptCount: attemptCount
            )
        }
        attemptCount += 1
        let data = try encoding.encode(nil)
        try checkCancellation()
        return data
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
