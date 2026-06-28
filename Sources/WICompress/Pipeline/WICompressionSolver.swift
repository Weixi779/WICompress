//
//  WICompressionSolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import CoreGraphics

enum WICompressionSolver {
    private static let defaultMaxEncodeAttempts = 40
    private static let maxSoftGeometryEncodeAttempts = 8

    static func compress(
        _ imageSource: WIImageSource,
        to target: WICompressionTarget,
        sourceColorSpace: WISourceColorSpaceInfo?,
        maxEncodeAttempts: Int = defaultMaxEncodeAttempts
    ) throws(WICompressError) -> Data {
        let initialPlan = try WICompressionTargetResolver.writePlan(
            for: target,
            info: imageSource.info,
            sourceColorSpace: sourceColorSpace
        )

        guard initialPlan.destinationFormat.supportsLossyQuality,
              initialPlan.quality != nil else {
            if initialPlan.destinationFormat == .png {
                return try solveLossless(
                    imageSource,
                    target: target,
                    sourceColorSpace: sourceColorSpace,
                    initialPlan: initialPlan,
                    maxEncodeAttempts: maxEncodeAttempts
                )
            }

            return try WIImageEncoder.encode(imageSource, plan: initialPlan)
        }

        let profile = WILossyQualityProfile(format: initialPlan.destinationFormat)
        let referencePixelSize = referencePixelSize(
            for: target.geometry,
            info: imageSource.info,
            initialPlan: initialPlan
        )
        let allowsDimensionSearch = allowsDimensionSearch(for: target.geometry)
        var currentLongSide = initialLongSide(for: target.geometry, info: imageSource.info, plan: initialPlan)
        var longSideOverride: Int?
        var highQuality = profile.qHigh
        var attemptCount = 0
        var smallestByteCount: Int?
        var candidates: [WISolvedCompressionCandidate] = []

        while true {
            if shouldReturnBestCandidate(
                candidates,
                allowsDimensionSearch: allowsDimensionSearch,
                attemptCount: attemptCount,
                maxEncodeAttempts: maxEncodeAttempts
            ) {
                return bestCandidate(
                    candidates,
                    preference: target.preference,
                    referencePixelSize: referencePixelSize
                ).data
            }

            let plan = try writePlan(
                for: target,
                info: imageSource.info,
                sourceColorSpace: sourceColorSpace,
                maxLongSide: longSideOverride
            )
            let renderedImage = try renderedImageIfNeeded(imageSource, plan: plan)
            let outputPixelSize = outputPixelSize(
                for: plan,
                renderedImage: renderedImage,
                info: imageSource.info
            )
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
                    allowEmergency: !allowsDimensionSearch,
                    attemptCount: &attemptCount,
                    maxEncodeAttempts: maxEncodeAttempts
                )
            } catch WICompressError.resourceLimitExceeded {
                if !candidates.isEmpty {
                    return bestCandidate(
                        candidates,
                        preference: target.preference,
                        referencePixelSize: referencePixelSize
                    ).data
                }
                throw WICompressError.resourceLimitExceeded(attemptCount: attemptCount)
            }

            if let candidate = outcome.candidate {
                candidates.append(candidate)
                if !allowsDimensionSearch ||
                    candidate.quality >= highQuality {
                    return bestCandidate(
                        candidates,
                        preference: target.preference,
                        referencePixelSize: referencePixelSize
                    ).data
                }
            }

            smallestByteCount = minByteCount(smallestByteCount, outcome.smallestByteCount)
            guard allowsDimensionSearch else {
                throw WICompressError.targetUnsatisfiable(smallestByteCount: smallestByteCount)
            }

            guard let estimateByteCount = outcome.dimensionSearchByteCount ?? outcome.smallestByteCount,
                  let nextLongSide = nextLongSide(
                    current: currentLongSide,
                    encodedBytes: estimateByteCount,
                    maxBytes: target.maxBytes,
                    format: plan.destinationFormat
                  ) else {
                if !candidates.isEmpty {
                    return bestCandidate(
                        candidates,
                        preference: target.preference,
                        referencePixelSize: referencePixelSize
                    ).data
                }
                throw WICompressError.targetUnsatisfiable(smallestByteCount: smallestByteCount)
            }

            currentLongSide = nextLongSide
            longSideOverride = nextLongSide
            highQuality = profile.qAnchor
        }
    }

    private static func solveLossless(
        _ imageSource: WIImageSource,
        target: WICompressionTarget,
        sourceColorSpace: WISourceColorSpaceInfo?,
        initialPlan: WIWritePlan,
        maxEncodeAttempts: Int
    ) throws(WICompressError) -> Data {
        let allowsDimensionSearch = allowsDimensionSearch(for: target.geometry)
        var currentLongSide = initialLongSide(for: target.geometry, info: imageSource.info, plan: initialPlan)
        var longSideOverride: Int?
        var attemptCount = 0
        var smallestByteCount: Int?

        while true {
            let plan = try writePlan(
                for: target,
                info: imageSource.info,
                sourceColorSpace: sourceColorSpace,
                maxLongSide: longSideOverride
            )
            let renderedImage = try renderedImageIfNeeded(imageSource, plan: plan)
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

            smallestByteCount = minByteCount(smallestByteCount, data.count)
            guard allowsDimensionSearch else {
                throw WICompressError.targetUnsatisfiable(smallestByteCount: smallestByteCount)
            }

            guard let nextLongSide = nextLongSide(
                current: currentLongSide,
                encodedBytes: data.count,
                maxBytes: target.maxBytes,
                format: plan.destinationFormat
            ) else {
                throw WICompressError.targetUnsatisfiable(smallestByteCount: smallestByteCount)
            }

            currentLongSide = nextLongSide
            longSideOverride = nextLongSide
        }
    }

    private static func solveFixedSize(
        _ imageSource: WIImageSource,
        plan: WIWritePlan,
        renderedImage: CGImage?,
        outputPixelSize: WIPixelSize,
        maxBytes: Int,
        profile: WILossyQualityProfile,
        highQuality: Double,
        allowEmergency: Bool,
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

        guard allowEmergency else {
            return WIFixedSizeSolveOutcome(
                candidate: nil,
                smallestByteCount: min(highData.count, kneeData.count),
                dimensionSearchByteCount: min(highData.count, kneeData.count)
            )
        }

        let emergencyData = try encode(
            imageSource,
            plan: plan,
            renderedImage: renderedImage,
            quality: profile.qEmergency,
            attemptCount: &attemptCount,
            maxEncodeAttempts: maxEncodeAttempts
        )
        if emergencyData.count <= maxBytes {
            let candidate = try searchQuality(
                imageSource,
                plan: plan,
                renderedImage: renderedImage,
                maxBytes: maxBytes,
                lowQuality: profile.qEmergency,
                highQuality: profile.qKnee,
                lowData: emergencyData,
                outputPixelSize: outputPixelSize,
                destinationFormat: plan.destinationFormat,
                attemptCount: &attemptCount,
                maxEncodeAttempts: maxEncodeAttempts
            )
            return WIFixedSizeSolveOutcome(
                candidate: candidate,
                smallestByteCount: emergencyData.count,
                dimensionSearchByteCount: highData.count
            )
        }

        return WIFixedSizeSolveOutcome(
            candidate: nil,
            smallestByteCount: min(highData.count, kneeData.count, emergencyData.count),
            dimensionSearchByteCount: min(highData.count, kneeData.count, emergencyData.count)
        )
    }

    private static func searchQuality(
        _ imageSource: WIImageSource,
        plan: WIWritePlan,
        renderedImage: CGImage?,
        maxBytes: Int,
        lowQuality: Double,
        highQuality: Double,
        lowData: Data,
        outputPixelSize: WIPixelSize,
        destinationFormat: WIImageFormat,
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
        plan: WIWritePlan,
        renderedImage: CGImage?,
        quality: Double?,
        attemptCount: inout Int,
        maxEncodeAttempts: Int
    ) throws(WICompressError) -> Data {
        guard attemptCount < maxEncodeAttempts else {
            throw WICompressError.resourceLimitExceeded(attemptCount: attemptCount)
        }

        attemptCount += 1

        var qualityPlan = plan
        qualityPlan.quality = quality
        if let renderedImage {
            return try WIImageEncoder.encodeRendered(renderedImage, imageSource: imageSource, plan: qualityPlan)
        }

        return try WIImageEncoder.encode(imageSource, plan: qualityPlan)
    }

    private static func renderedImageIfNeeded(
        _ imageSource: WIImageSource,
        plan: WIWritePlan
    ) throws(WICompressError) -> CGImage? {
        switch plan.path {
        case .redrawBitmap, .redrawCanvas:
            return try WIImageEncoder.render(imageSource, plan: plan)
        case .returnOriginal, .copyFromSource:
            return nil
        }
    }

    private static func writePlan(
        for target: WICompressionTarget,
        info: WIImageInfo,
        sourceColorSpace: WISourceColorSpaceInfo?,
        maxLongSide: Int?
    ) throws(WICompressError) -> WIWritePlan {
        guard let maxLongSide else {
            return try WICompressionTargetResolver.writePlan(
                for: target,
                info: info,
                sourceColorSpace: sourceColorSpace
            )
        }

        var options = try WICompressionTargetResolver.options(for: target)
        options.resize = .maxPixel(maxLongSide)
        return try WIWritePlanResolver.resolve(
            options: options,
            info: info,
            sourceColorSpace: sourceColorSpace
        )
    }

    private static func initialLongSide(
        for geometry: WICompressionGeometry,
        info: WIImageInfo,
        plan: WIWritePlan
    ) -> Int {
        switch geometry {
        case .fill, .exactCanvas:
            if let canvasSize = plan.renderGeometry?.canvasSize {
                return max(canvasSize.width, canvasSize.height)
            }
        case .original, .fit, .fitInside:
            if let targetPixelSize = plan.targetPixelSize {
                return max(targetPixelSize.width, targetPixelSize.height)
            }
            if let maxPixelSize = plan.maxPixelSize {
                return maxPixelSize
            }
        }

        return max(info.displayWidth, info.displayHeight)
    }

    private static func referencePixelSize(
        for geometry: WICompressionGeometry,
        info: WIImageInfo,
        initialPlan: WIWritePlan
    ) -> WIPixelSize {
        switch geometry {
        case .fill, .exactCanvas:
            if let canvasSize = initialPlan.renderGeometry?.canvasSize {
                return canvasSize
            }
        case .original, .fit, .fitInside:
            if let targetPixelSize = initialPlan.targetPixelSize {
                return targetPixelSize
            }
            if let maxPixelSize = initialPlan.maxPixelSize {
                return scaledPixelSize(
                    source: WIPixelSize(width: info.displayWidth, height: info.displayHeight),
                    maxLongSide: maxPixelSize
                )
            }
        }

        return WIPixelSize(width: info.displayWidth, height: info.displayHeight)
    }

    private static func outputPixelSize(
        for plan: WIWritePlan,
        renderedImage: CGImage?,
        info: WIImageInfo
    ) -> WIPixelSize {
        if let renderedImage {
            return WIPixelSize(width: renderedImage.width, height: renderedImage.height)
        }

        if let canvasSize = plan.renderGeometry?.canvasSize {
            return canvasSize
        }

        if let targetPixelSize = plan.targetPixelSize {
            return targetPixelSize
        }

        if let maxPixelSize = plan.maxPixelSize {
            return scaledPixelSize(
                source: WIPixelSize(width: info.displayWidth, height: info.displayHeight),
                maxLongSide: maxPixelSize
            )
        }

        return WIPixelSize(width: info.displayWidth, height: info.displayHeight)
    }

    private static func scaledPixelSize(source: WIPixelSize, maxLongSide: Int) -> WIPixelSize {
        let sourceLongSide = max(source.width, source.height)
        guard sourceLongSide > 0, maxLongSide < sourceLongSide else {
            return source
        }

        let scale = Double(max(maxLongSide, 1)) / Double(sourceLongSide)
        return WIPixelSize(
            width: max(Int((Double(source.width) * scale).rounded(.toNearestOrAwayFromZero)), 1),
            height: max(Int((Double(source.height) * scale).rounded(.toNearestOrAwayFromZero)), 1)
        )
    }

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

    private static func shouldReturnBestCandidate(
        _ candidates: [WISolvedCompressionCandidate],
        allowsDimensionSearch: Bool,
        attemptCount: Int,
        maxEncodeAttempts: Int
    ) -> Bool {
        guard allowsDimensionSearch, !candidates.isEmpty else {
            return false
        }

        let remainingAttempts = max(maxEncodeAttempts - attemptCount, 0)
        return remainingAttempts < maxSoftGeometryEncodeAttempts
    }

    private static func allowsDimensionSearch(for geometry: WICompressionGeometry) -> Bool {
        switch geometry {
        case .original, .fit, .fitInside:
            return true
        case .fill, .exactCanvas:
            return false
        }
    }

    private static func nextLongSide(
        current: Int,
        encodedBytes: Int,
        maxBytes: Int,
        format: WIImageFormat
    ) -> Int? {
        guard current > 1, encodedBytes > maxBytes else {
            return nil
        }

        let overhead = 512.0
        let adjustedTarget = max(Double(maxBytes) - overhead, 1)
        let adjustedBytes = max(Double(encodedBytes) - overhead, 1)
        let scale = sqrt(adjustedTarget / adjustedBytes) * 0.92
        var next = min(current - 1, max(Int((Double(current) * scale).rounded(.down)), 1))

        if format == .heif, next > 2, next % 2 != 0 {
            next -= 1
        }

        return next < current ? next : nil
    }

    private static func minByteCount(_ lhs: Int?, _ rhs: Int?) -> Int? {
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

private struct WILossyQualityProfile: Sendable, Equatable {
    var qHigh: Double
    var qAnchor: Double
    var qKnee: Double
    var qEmergency: Double

    private init(qHigh: Double, qAnchor: Double, qKnee: Double, qEmergency: Double) {
        self.qHigh = qHigh
        self.qAnchor = qAnchor
        self.qKnee = qKnee
        self.qEmergency = qEmergency
    }

    init(format: WIImageFormat) {
        switch format {
        case .jpeg:
            self.init(qHigh: 0.82, qAnchor: 0.72, qKnee: 0.45, qEmergency: 0.24)
        case .heif:
            self.init(qHigh: 0.78, qAnchor: 0.68, qKnee: 0.42, qEmergency: 0.22)
        case .png, .unknown:
            self.init(qHigh: 0, qAnchor: 0, qKnee: 0, qEmergency: 0)
        }
    }
}

struct WISolvedCompressionCandidate: Sendable, Equatable {
    var data: Data
    var pixelSize: WIPixelSize
    var format: WIImageFormat
    var quality: Double

    var pixelArea: Double {
        Double(pixelSize.width) * Double(pixelSize.height)
    }
}

private struct WIFixedSizeSolveOutcome: Sendable, Equatable {
    var candidate: WISolvedCompressionCandidate?
    var smallestByteCount: Int?
    var dimensionSearchByteCount: Int?
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
