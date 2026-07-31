//
//  WIImageDomainTests.swift
//  WIImageDomainTests
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Testing
@testable import WIImageDomain

@Suite("WIImageDomain")
struct WIImageDomainTests {
    @Test("Pixel size normalizes non-positive dimensions")
    func pixelSizeNormalization() {
        #expect(WIPixelSize(width: 40, height: 20).width == 40)
        #expect(WIPixelSize(width: 0, height: -10) == WIPixelSize(width: 1, height: 1))
    }

    @Test(
        "WIImageOrientation identifies display-axis swaps",
        arguments: WIImageOrientation.allCases
    )
    func orientationAxisSwap(_ orientation: WIImageOrientation) {
        let expected = [5, 6, 7, 8].contains(orientation.rawValue)

        #expect(orientation.swapsDimensions == expected)
    }

    @Test("Metadata aliases compose as standard OptionSet values")
    func metadataOptions() {
        let withoutGPS = WIImageMetadataOptions.preserve
            .subtracting(.gps)

        #expect(WIImageMetadataOptions.strip.isEmpty)
        #expect(WIImageMetadataOptions.preserve == .all)
        #expect(withoutGPS.contains(.exif))
        #expect(withoutGPS.contains(.iptc))
        #expect(withoutGPS.contains(.tiff))
        #expect(withoutGPS.contains(.makerNotes))
        #expect(!withoutGPS.contains(.gps))
    }
}
