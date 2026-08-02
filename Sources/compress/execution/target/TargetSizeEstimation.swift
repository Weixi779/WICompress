//
//  TargetSizeEstimation.swift
//  WICompressExecution
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

/// Pure dimension estimation for target byte-budget searches.
enum TargetSizeEstimation {
    static func nextLongSide(
        current: Int,
        encodedBytes: Int,
        maxBytes: Int,
        format: ImageFormat
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

    static func scaledPixelSize(source: WIPixelSize, maxLongSide: Int) -> WIPixelSize {
        let sourceLongSide = max(source.width, source.height)
        guard sourceLongSide > 0, maxLongSide < sourceLongSide else {
            return source
        }

        let scale = Double(max(maxLongSide, 1)) / Double(sourceLongSide)
        return WIPixelSize(
            validWidth: max(
                Int((Double(source.width) * scale).rounded(.toNearestOrAwayFromZero)),
                1
            ),
            height: max(Int((Double(source.height) * scale).rounded(.toNearestOrAwayFromZero)), 1)
        )
    }
}
