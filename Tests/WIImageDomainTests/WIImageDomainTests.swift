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

    @Test("Crop anchors clamp to the normalized coordinate space")
    func cropAnchorNormalization() {
        #expect(WICropAnchor(x: -0.2, y: 1.2) == WICropAnchor(x: 0, y: 1))
        #expect(WICropAnchor(x: .nan, y: .nan) == .center)
    }

    @Test("Process quality clamps and recovers NaN to the default")
    func processQualityNormalization() {
        #expect(WIImageProcess(quality: -0.2).quality == 0)
        #expect(WIImageProcess(quality: 1.2).quality == 1)
        #expect(WIImageProcess(quality: .nan).quality == 0.6)
        #expect(WIImageProcess(quality: nil).quality == nil)
    }

    @Test("Numeric sizing bounds normalize when one pixel is meaningful")
    func sizingNormalization() {
        #expect(
            WICompressionSizing(maximumPixelSize: 0).maximumPixelSize == 1
        )
        #expect(
            WIImageResize.maximumPixelSize(-10)
                == WIImageResize.maximumPixelSize(1)
        )
    }

    @Test("Invalid ratios and targets fail during construction")
    func hardConstraintValidation() {
        #expect(throws: WICompressError.invalidCrop) {
            try WIAspectRatio(width: 0, height: 1)
        }
        #expect(throws: WICompressError.invalidCrop) {
            try WIAspectRatio(width: 1, height: .nan)
        }
        #expect(throws: WICompressError.invalidTarget) {
            try WICompressionTarget(maxBytes: 0)
        }
        #expect(throws: WICompressError.invalidResizing) {
            try WIImageResize.scaled(by: 0)
        }
    }

    @Test(
        "Orientation identifies display-axis swaps",
        arguments: Orientation.allCases
    )
    func orientationAxisSwap(_ orientation: Orientation) {
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
