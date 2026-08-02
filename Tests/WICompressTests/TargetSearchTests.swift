//
//  TargetSearchTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import Testing
import WICompress
@testable import WICompressExecution

@Suite("Target Search", .tags(.algorithm))
struct TargetSearchTests {

    @Test("Lossy search with no attempt budget prepares but does not encode")
    func lossySearchStopsBeforeFirstEncode() {
        let probe = SearchProbe()
        var search = lossySearch(
            maxEncodeAttempts: 0,
            probe: probe
        )

        #expect(throws: WICompressError.resourceLimitExceeded(attemptCount: 0)) {
            _ = try search.run()
        }
        #expect(probe.preparedPixelSizes == [Self.basePixelSize])
        #expect(probe.initialQualities == [0.82])
        #expect(probe.encodedQualities.isEmpty)
    }

    @Test("Lossy search counts the first encode before rejecting the knee encode")
    func lossySearchStopsAfterFirstEncode() {
        let probe = SearchProbe()
        var search = lossySearch(
            maxEncodeAttempts: 1,
            probe: probe
        )

        #expect(throws: WICompressError.resourceLimitExceeded(attemptCount: 1)) {
            _ = try search.run()
        }
        #expect(probe.preparedPixelSizes == [Self.basePixelSize])
        #expect(probe.initialQualities == [0.82])
        #expect(probe.encodedQualities == [0.82])
    }

    @Test("Lossy search returns its candidate when another fixed-size search cannot fit the budget")
    func lossySearchReturnsCandidateBeforePreparingAnotherSize() throws {
        let probe = SearchProbe()
        var search = LossyTargetSearch(
            maxBytes: 100,
            format: .jpeg,
            basePixelSize: Self.basePixelSize,
            maxEncodeAttempts: 12
        ) { pixelSize, initialQuality in
            probe.recordPreparation(pixelSize, initialQuality: initialQuality)
            return PreparedTargetEncoding(pixelSize: pixelSize) { quality in
                probe.encodedQualities.append(quality)
                guard let quality, quality <= 0.6 else {
                    return Data(count: 200)
                }
                return Data(count: Int((quality * 100).rounded()))
            }
        }

        let data = try search.run()

        #expect(data.count == 59)
        #expect(probe.preparedPixelSizes == [Self.basePixelSize])
        #expect(probe.initialQualities == [0.82])
        #expect(probe.encodedQualities.count == 8)
        #expect(probe.encodedQualities.prefix(2) == [0.82, 0.45])
    }

    @Test("PNG search with no attempt budget prepares but does not encode")
    func pngSearchStopsBeforeFirstEncode() {
        let probe = SearchProbe()
        var search = pngSearch(
            maxEncodeAttempts: 0,
            probe: probe
        )

        #expect(throws: WICompressError.resourceLimitExceeded(attemptCount: 0)) {
            _ = try search.run()
        }
        #expect(probe.preparedPixelSizes == [Self.basePixelSize])
        #expect(probe.encodedQualities.isEmpty)
    }

    @Test("PNG search prepares its next size before the second encode exhausts the budget")
    func pngSearchStopsBeforeSecondEncode() {
        let probe = SearchProbe()
        var search = pngSearch(
            maxEncodeAttempts: 1,
            probe: probe
        )

        #expect(throws: WICompressError.resourceLimitExceeded(attemptCount: 1)) {
            _ = try search.run()
        }
        #expect(probe.preparedPixelSizes.count == 2)
        #expect(probe.preparedPixelSizes.first == Self.basePixelSize)
        #expect(probe.preparedPixelSizes.last != Self.basePixelSize)
        #expect(probe.encodedQualities == [nil])
    }

    private static let basePixelSize = WIPixelSize(width: 100, height: 50)

    private func lossySearch(
        maxEncodeAttempts: Int,
        probe: SearchProbe
    ) -> LossyTargetSearch {
        LossyTargetSearch(
            maxBytes: 100,
            format: .jpeg,
            basePixelSize: Self.basePixelSize,
            maxEncodeAttempts: maxEncodeAttempts
        ) { pixelSize, initialQuality in
            probe.recordPreparation(pixelSize, initialQuality: initialQuality)
            return PreparedTargetEncoding(pixelSize: pixelSize) { quality in
                probe.encodedQualities.append(quality)
                return Data(count: 200)
            }
        }
    }

    private func pngSearch(
        maxEncodeAttempts: Int,
        probe: SearchProbe
    ) -> PNGTargetSearch {
        PNGTargetSearch(
            maxBytes: 100,
            basePixelSize: Self.basePixelSize,
            maxEncodeAttempts: maxEncodeAttempts
        ) { pixelSize in
            probe.preparedPixelSizes.append(pixelSize)
            return PreparedTargetEncoding(pixelSize: pixelSize) { quality in
                probe.encodedQualities.append(quality)
                return Data(count: 200)
            }
        }
    }
}

private final class SearchProbe {
    var preparedPixelSizes: [WIPixelSize] = []
    var initialQualities: [Double] = []
    var encodedQualities: [Double?] = []

    func recordPreparation(
        _ pixelSize: WIPixelSize,
        initialQuality: Double
    ) {
        preparedPixelSizes.append(pixelSize)
        initialQualities.append(initialQuality)
    }
}
