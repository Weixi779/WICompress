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
    @Test("Pixel size owns positive checked dimensions")
    func pixelSizeValidation() throws {
        let size = try WIPixelSize(
            validatingWidth: 40,
            height: 20
        )

        #expect(size.pixelCount == 800)
        #expect(
            throws: WIPixelSize.ValidationError.invalidDimensions(
                width: 0,
                height: 10
            )
        ) {
            try WIPixelSize(validatingWidth: 0, height: 10)
        }
        #expect(
            throws: WIPixelSize.ValidationError.pixelCountOverflow(
                width: .max,
                height: 2
            )
        ) {
            try WIPixelSize(validatingWidth: .max, height: 2)
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
}
