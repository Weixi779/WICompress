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
        "WIImageOrientation resolves display pixel dimensions",
        arguments: WIImageOrientation.allCases
    )
    func orientationAxisSwap(_ orientation: WIImageOrientation) {
        let storedSize = WIPixelSize(width: 40, height: 20)
        let swapsDimensions = [5, 6, 7, 8].contains(orientation.rawValue)
        let expectedSize = swapsDimensions
            ? WIPixelSize(width: 20, height: 40)
            : storedSize

        #expect(orientation.swapsDimensions == swapsDimensions)
        #expect(storedSize.oriented(by: orientation) == expectedSize)
    }

    @Test("Metadata aliases compose as standard OptionSet values")
    func metadataOptions() {
        let withoutGPS = ImageMetadataOptions.preserve
            .subtracting(.gps)

        #expect(ImageMetadataOptions.strip.isEmpty)
        #expect(ImageMetadataOptions.preserve == .all)
        #expect(withoutGPS.contains(.exif))
        #expect(withoutGPS.contains(.iptc))
        #expect(withoutGPS.contains(.tiff))
        #expect(withoutGPS.contains(.makerNotes))
        #expect(!withoutGPS.contains(.gps))
    }
}
