//
//  WICompressDomainTests.swift
//  WICompressDomainTests
//
//  Created by weixi on 2026/8/1.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Testing
import WIImageDomain
@testable import WICompressDomain

@Suite("WICompressDomain")
struct WICompressDomainTests {
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
}
