//
//  WILuban.swift
//  WICompressDomain
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

enum WILuban {

    // MARK: - Luban 1

    static func ensureEven(_ size: Int) -> Int {
        guard !size.isMultiple(of: 2) else {
            return size
        }

        let (incrementedSize, overflow) = size.addingReportingOverflow(1)
        return overflow ? size - 1 : incrementedSize
    }

    static func legacyScaleFactor(width: Int, height: Int) -> Int {
        let longSide = max(ensureEven(width), ensureEven(height))
        let shortSide = min(ensureEven(width), ensureEven(height))
        let aspectRatio = Double(shortSide) / Double(longSide)

        switch aspectRatio {
        case 0.5625...1 where longSide < 1664:
            return 1
        case 0.5625...1 where longSide < 4990:
            return 2
        case 0.5625...1 where longSide < 10240:
            return 4
        case 0.5625...1:
            return max(longSide / 1280, 1)
        case 0.5..<0.5625:
            return longSide > 1280 ? max(longSide / 1280, 1) : 1
        default:
            // Original Luban uses `ceil(longSide / (1280 / scale))` where
            // `scale = shortSide / longSide`, which simplifies to
            // `ceil(shortSide / 1280)`. Dividing the long side here over-shrinks
            // very long images (e.g. panoramas / long screenshots).
            return max(Int(ceil(Double(shortSide) / 1280.0)), 1)
        }
    }

    // MARK: - Luban 2

    private static let v2BaseShortSide = 1_440
    private static let v2WallLongSide = 10_800
    private static let v2WallRatioNumerator = 2
    private static let v2WallRatioDenominator = 5
    private static let v2LargeSourcePixelCount = 40_960_000
    private static let v2MaximumTargetPixelCount = 10_240_000

    static func v2TargetSize(
        for sourceSize: WIPixelSize
    ) throws(WICompressError) -> WIPixelSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            throw .invalidResizing
        }

        let sourceShortSide = min(sourceSize.width, sourceSize.height)
        let sourceLongSide = max(sourceSize.width, sourceSize.height)
        let usesWallSizing = sourceLongSide >= v2WallLongSide
            && isGreaterThanWallRatio(
                shortSide: sourceShortSide,
                longSide: sourceLongSide
            )

        var targetShortSide: Int
        var targetLongSide: Int
        if usesWallSizing {
            targetShortSide = try proportionalShortSide(
                for: v2BaseShortSide,
                sourceShortSide: sourceShortSide,
                sourceLongSide: sourceLongSide
            )
            targetLongSide = v2BaseShortSide
        } else if sourceShortSide <= v2BaseShortSide {
            targetShortSide = sourceShortSide
            targetLongSide = sourceLongSide
        } else {
            targetShortSide = v2BaseShortSide
            targetLongSide = try proportionalLongSide(
                for: targetShortSide,
                sourceShortSide: sourceShortSide,
                sourceLongSide: sourceLongSide
            )
        }

        let (sourcePixelCount, sourcePixelCountOverflow) = sourceSize.width
            .multipliedReportingOverflow(by: sourceSize.height)
        let exceedsLargeSourceThreshold = sourcePixelCountOverflow
            || sourcePixelCount > v2LargeSourcePixelCount
        if exceedsLargeSourceThreshold {
            let reducedShortSide = max(sourceShortSide / 4, 1)
            if reducedShortSide < targetShortSide {
                targetShortSide = reducedShortSide
                targetLongSide = try proportionalLongSide(
                    for: targetShortSide,
                    sourceShortSide: sourceShortSide,
                    sourceLongSide: sourceLongSide
                )
            }
        }

        let targetPixelCount = Double(targetShortSide)
            * Double(targetLongSide)
        if targetPixelCount > Double(v2MaximumTargetPixelCount) {
            let exactScale = sqrt(
                Double(v2MaximumTargetPixelCount) / targetPixelCount
            )
            let quantizedScale = floor(exactScale * 1_000) / 1_000
            let scale = quantizedScale > 0 ? quantizedScale : exactScale
            targetShortSide = try integer(Double(targetShortSide) * scale)
            targetLongSide = try integer(Double(targetLongSide) * scale)
        }

        targetShortSide = normalizedEvenDimension(targetShortSide)
        targetLongSide = normalizedEvenDimension(targetLongSide)
        if exceedsPixelCountLimit(
            width: targetShortSide,
            height: targetLongSide
        ) {
            targetLongSide = normalizedEvenDimension(
                v2MaximumTargetPixelCount / targetShortSide
            )
        }

        if sourceSize.width < sourceSize.height {
            return WIPixelSize(
                width: targetShortSide,
                height: targetLongSide
            )
        }
        return WIPixelSize(
            width: targetLongSide,
            height: targetShortSide
        )
    }

    // MARK: - Luban 2 Arithmetic

    private static func proportionalLongSide(
        for shortSide: Int,
        sourceShortSide: Int,
        sourceLongSide: Int
    ) throws(WICompressError) -> Int {
        try multipliedDividing(
            shortSide,
            by: sourceLongSide,
            dividedBy: sourceShortSide
        )
    }

    private static func isGreaterThanWallRatio(
        shortSide: Int,
        longSide: Int
    ) -> Bool {
        let shortSideProduct = UInt(shortSide).multipliedFullWidth(
            by: UInt(v2WallRatioDenominator)
        )
        let longSideProduct = UInt(longSide).multipliedFullWidth(
            by: UInt(v2WallRatioNumerator)
        )
        if shortSideProduct.high != longSideProduct.high {
            return shortSideProduct.high > longSideProduct.high
        }
        return shortSideProduct.low > longSideProduct.low
    }

    private static func proportionalShortSide(
        for longSide: Int,
        sourceShortSide: Int,
        sourceLongSide: Int
    ) throws(WICompressError) -> Int {
        try multipliedDividing(
            longSide,
            by: sourceShortSide,
            dividedBy: sourceLongSide
        )
    }

    private static func multipliedDividing(
        _ value: Int,
        by multiplier: Int,
        dividedBy divisor: Int
    ) throws(WICompressError) -> Int {
        let product = UInt(value).multipliedFullWidth(
            by: UInt(multiplier)
        )
        let unsignedDivisor = UInt(divisor)
        guard product.high < unsignedDivisor else {
            throw .invalidResizing
        }

        let quotient = unsignedDivisor.dividingFullWidth(product).quotient
        guard let result = Int(exactly: quotient) else {
            throw .invalidResizing
        }
        return max(result, 1)
    }

    private static func integer(
        _ value: Double
    ) throws(WICompressError) -> Int {
        guard value.isFinite,
              let result = Int(exactly: value.rounded(.towardZero))
        else {
            throw .invalidResizing
        }
        return max(result, 1)
    }

    private static func normalizedEvenDimension(_ value: Int) -> Int {
        guard value > 1 else {
            return 1
        }
        return value.isMultiple(of: 2) ? value : value - 1
    }

    private static func exceedsPixelCountLimit(
        width: Int,
        height: Int
    ) -> Bool {
        let (pixelCount, overflow) = width.multipliedReportingOverflow(
            by: height
        )
        return overflow || pixelCount > v2MaximumTargetPixelCount
    }
}
