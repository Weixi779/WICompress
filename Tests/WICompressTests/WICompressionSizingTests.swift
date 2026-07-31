//
//  WICompressionSizingTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Testing
import WICompress
@testable import WICompressExecution
@testable import WIImageDomain

@Suite("Compression Sizing", .tags(.algorithm))
struct WICompressionSizingTests {
    struct SizingCase: CustomTestStringConvertible, Sendable {
        let sizing: WICompressionSizing
        let expectedSourceRect: Rect
        let expectedBasePixelSize: WIPixelSize
        let testDescription: String
    }

    static let sizingCases: [SizingCase] = [
        SizingCase(
            sizing: WICompressionSizing(),
            expectedSourceRect: Rect(
                x: 0,
                y: 0,
                width: 4000,
                height: 3000
            ),
            expectedBasePixelSize: WIPixelSize(
                width: 4000,
                height: 3000
            ),
            testDescription: "00 uses the full source"
        ),
        SizingCase(
            sizing: WICompressionSizing(
                aspectRatio: .square
            ),
            expectedSourceRect: Rect(
                x: 500,
                y: 0,
                width: 3000,
                height: 3000
            ),
            expectedBasePixelSize: WIPixelSize(
                width: 3000,
                height: 3000
            ),
            testDescription: "01 resolves the largest centered ratio crop"
        ),
        SizingCase(
            sizing: WICompressionSizing(maximumPixelSize: 1000),
            expectedSourceRect: Rect(
                x: 0,
                y: 0,
                width: 4000,
                height: 3000
            ),
            expectedBasePixelSize: WIPixelSize(
                width: 1000,
                height: 750
            ),
            testDescription: "10 limits the longest side proportionally"
        ),
        SizingCase(
            sizing: WICompressionSizing(
                maximumPixelSize: 1000,
                aspectRatio: .square
            ),
            expectedSourceRect: Rect(
                x: 500,
                y: 0,
                width: 3000,
                height: 3000
            ),
            expectedBasePixelSize: WIPixelSize(
                width: 1000,
                height: 1000
            ),
            testDescription: "11 crops before applying the maximum"
        ),
    ]

    @Test(
        "Sizing resolves all four optional-input combinations",
        arguments: sizingCases
    )
    func sizingResolvesFourCombinations(
        _ sizingCase: SizingCase
    ) throws {
        let resolved = try sizingCase.sizing.geometry(
            for: WIPixelSize(width: 4000, height: 3000)
        )

        #expect(resolved.sourceRect == sizingCase.expectedSourceRect)
        #expect(resolved.basePixelSize == sizingCase.expectedBasePixelSize)
    }

    @Test("Aspect-ratio anchor moves the fixed crop without changing its size")
    func aspectRatioAnchorMovesCrop() throws {
        let resolved = try WICompressionSizing(
                aspectRatio: .square,
                anchor: WICropAnchor(x: 0, y: 0.5)
            )
            .geometry(for: WIPixelSize(width: 4000, height: 3000))

        #expect(
            resolved.sourceRect == Rect(
                x: 0,
                y: 0,
                width: 3000,
                height: 3000
            )
        )
        #expect(
            resolved.basePixelSize == WIPixelSize(
                width: 3000,
                height: 3000
            )
        )
    }
}
