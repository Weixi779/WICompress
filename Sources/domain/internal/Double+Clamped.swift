//
//  Double+Clamped.swift
//  WIImageDomain
//
//  Created by weixi on 2026/7/31.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

extension Double {
    package func clamped(
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard !isNaN else {
            return fallback
        }

        return min(max(self, range.lowerBound), range.upperBound)
    }
}
