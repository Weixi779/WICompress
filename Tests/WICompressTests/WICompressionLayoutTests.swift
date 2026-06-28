//
//  WICompressionLayoutTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Testing
@testable import WICompress

@Suite("Compression Layout", .tags(.algorithm))
struct WICompressionLayoutTests {

    struct LayoutCase: CustomTestStringConvertible, Sendable {
        let source: WIPixelSize
        let canvas: WIPixelSize
        let placement: WIImagePlacement
        let expected: WIRect
        let testDescription: String
    }

    // Canvas geometry is bottom-left origin (y-up): a higher `y` is nearer the top.
    static let layoutCases: [LayoutCase] = [
        LayoutCase(
            source: WIPixelSize(width: 8, height: 4),
            canvas: WIPixelSize(width: 4, height: 4),
            placement: .stretch,
            expected: WIRect(x: 0, y: 0, width: 4, height: 4),
            testDescription: "stretch fills the canvas exactly"
        ),
        LayoutCase(
            source: WIPixelSize(width: 8, height: 4),
            canvas: WIPixelSize(width: 4, height: 4),
            placement: .fit(.center),
            expected: WIRect(x: 0, y: 1, width: 4, height: 2),
            testDescription: "fit center letterboxes vertically"
        ),
        LayoutCase(
            source: WIPixelSize(width: 8, height: 4),
            canvas: WIPixelSize(width: 4, height: 4),
            placement: .fit(.top),
            expected: WIRect(x: 0, y: 2, width: 4, height: 2),
            testDescription: "fit top pins content to the top edge"
        ),
        LayoutCase(
            source: WIPixelSize(width: 8, height: 4),
            canvas: WIPixelSize(width: 4, height: 4),
            placement: .fit(.bottom),
            expected: WIRect(x: 0, y: 0, width: 4, height: 2),
            testDescription: "fit bottom pins content to the bottom edge"
        ),
        LayoutCase(
            source: WIPixelSize(width: 8, height: 4),
            canvas: WIPixelSize(width: 4, height: 4),
            placement: .fill(.center),
            expected: WIRect(x: -2, y: 0, width: 8, height: 4),
            testDescription: "fill center overflows horizontally and is centered"
        ),
        LayoutCase(
            source: WIPixelSize(width: 8, height: 4),
            canvas: WIPixelSize(width: 4, height: 4),
            placement: .fill(.left),
            expected: WIRect(x: 0, y: 0, width: 8, height: 4),
            testDescription: "fill left keeps the left edge"
        ),
        LayoutCase(
            source: WIPixelSize(width: 8, height: 4),
            canvas: WIPixelSize(width: 4, height: 4),
            placement: .fill(.right),
            expected: WIRect(x: -4, y: 0, width: 8, height: 4),
            testDescription: "fill right keeps the right edge"
        ),
        LayoutCase(
            source: WIPixelSize(width: 4, height: 8),
            canvas: WIPixelSize(width: 4, height: 4),
            placement: .fill(.top),
            expected: WIRect(x: 0, y: -4, width: 4, height: 8),
            testDescription: "fill top keeps the top of a tall source"
        ),
        LayoutCase(
            source: WIPixelSize(width: 4, height: 8),
            canvas: WIPixelSize(width: 4, height: 4),
            placement: .fill(.bottom),
            expected: WIRect(x: 0, y: 0, width: 4, height: 8),
            testDescription: "fill bottom keeps the bottom of a tall source"
        ),
    ]

    @Test("destinationRect places content per scale mode and anchor", arguments: layoutCases)
    func destinationRectPlacesContent(_ layoutCase: LayoutCase) {
        let rect = WICompressionLayout.destinationRect(
            sourceSize: layoutCase.source,
            canvasSize: layoutCase.canvas,
            placement: layoutCase.placement
        )

        #expect(rect == layoutCase.expected)
    }
}
