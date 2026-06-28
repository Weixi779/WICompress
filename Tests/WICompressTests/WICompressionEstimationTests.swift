//
//  WICompressionEstimationTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Testing
@testable import WICompress

@Suite("Compression Size Estimation", .tags(.algorithm))
struct WICompressionEstimationTests {

    @Test("nextLongSide returns nil once the longest side reaches one pixel")
    func nextLongSideStopsAtOnePixel() {
        #expect(
            WICompressionSizeEstimation.nextLongSide(
                current: 1,
                encodedBytes: 100_000,
                maxBytes: 1_000,
                format: .jpeg
            ) == nil
        )
    }

    @Test("nextLongSide returns nil when the encoded size already fits")
    func nextLongSideStopsWhenWithinBudget() {
        #expect(
            WICompressionSizeEstimation.nextLongSide(
                current: 1_000,
                encodedBytes: 5_000,
                maxBytes: 5_000,
                format: .jpeg
            ) == nil
        )
    }

    @Test("nextLongSide shrinks aggressively when far over budget")
    func nextLongSideShrinksWhenFarOverBudget() {
        let next = try! #require(
            WICompressionSizeEstimation.nextLongSide(
                current: 1_000,
                encodedBytes: 100_000,
                maxBytes: 10_000,
                format: .jpeg
            )
        )

        // ~10x over budget on bytes should roughly cut the longest side to a third.
        #expect(next < 1_000)
        #expect(next > 200)
        #expect(next < 400)
    }

    @Test("nextLongSide shrinks by at least one pixel when barely over budget")
    func nextLongSideShrinksByAtLeastOnePixel() {
        #expect(
            WICompressionSizeEstimation.nextLongSide(
                current: 10,
                encodedBytes: 10_001,
                maxBytes: 10_000,
                format: .jpeg
            ) == 9
        )
    }

    @Test("nextLongSide aligns HEIF candidates to an even side")
    func nextLongSideAlignsHEIFToEvenSide() {
        // JPEG keeps the odd estimate; HEIF rounds the same estimate down to even.
        #expect(
            WICompressionSizeEstimation.nextLongSide(
                current: 10,
                encodedBytes: 10_001,
                maxBytes: 10_000,
                format: .jpeg
            ) == 9
        )
        #expect(
            WICompressionSizeEstimation.nextLongSide(
                current: 10,
                encodedBytes: 10_001,
                maxBytes: 10_000,
                format: .heif
            ) == 8
        )
    }

    @Test("scaledPixelSize never upscales")
    func scaledPixelSizeNeverUpscales() {
        let source = WIPixelSize(width: 1_000, height: 500)

        #expect(
            WICompressionSizeEstimation.scaledPixelSize(source: source, maxLongSide: 1_000) == source
        )
        #expect(
            WICompressionSizeEstimation.scaledPixelSize(source: source, maxLongSide: 2_000) == source
        )
    }

    @Test("scaledPixelSize downscales while preserving aspect ratio")
    func scaledPixelSizeDownscalesPreservingAspect() {
        let source = WIPixelSize(width: 1_000, height: 500)

        #expect(
            WICompressionSizeEstimation.scaledPixelSize(source: source, maxLongSide: 500)
                == WIPixelSize(width: 500, height: 250)
        )
    }

    @Test("scaledPixelSize clamps each side to at least one pixel")
    func scaledPixelSizeClampsToOnePixel() {
        let source = WIPixelSize(width: 1_000, height: 500)

        #expect(
            WICompressionSizeEstimation.scaledPixelSize(source: source, maxLongSide: 1)
                == WIPixelSize(width: 1, height: 1)
        )
    }
}
