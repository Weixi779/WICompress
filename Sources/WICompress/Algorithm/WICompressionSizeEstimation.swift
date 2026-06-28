//
//  WICompressionSizeEstimation.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Pure dimension and quality-profile math for the target byte-budget search.
///
/// The solver shrinks the longest side by an area-proportional estimate and
/// restarts a fresh quality search at the smaller size. These functions hold no
/// ImageIO or I/O state so they can be reasoned about and unit-tested directly.
enum WICompressionSizeEstimation {
    /// Estimates the next longest side from the encoded byte count, never growing
    /// and never over-shrinking past the safety margin. Returns `nil` once the
    /// search has converged.
    static func nextLongSide(
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

    /// Scales a pixel size so its longest side fits `maxLongSide`, preserving the
    /// aspect ratio and never upscaling.
    static func scaledPixelSize(source: WIPixelSize, maxLongSide: Int) -> WIPixelSize {
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
}

/// Lossy quality anchors searched at a fixed candidate size. Internal tuning;
/// never exposed through the public target API.
struct WILossyQualityProfile: Sendable, Equatable {
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
