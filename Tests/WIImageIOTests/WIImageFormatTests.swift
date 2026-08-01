//
//  WIImageFormatTests.swift
//  WIImageIOTests
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WIImageIO

@Suite("WIImageFormat Detection")
struct WIImageFormatTests {

    struct FormatCase: CustomTestStringConvertible, Sendable {
        let type: UTType
        let expected: WIImageFormat
        let testDescription: String
    }

    static let knownFormatCases: [FormatCase] = [
        FormatCase(type: .jpeg, expected: .jpeg, testDescription: "JPEG data"),
        FormatCase(type: .png, expected: .png, testDescription: "PNG data"),
    ]

    // MARK: - Helpers

    /// Renders a 1×1 CGImage into the given UTType using ImageIO.
    /// Available on macOS without UIKit.
    private static func makeImageData(type: UTType) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard
            let context = CGContext(
                data: nil, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 1,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ),
            let cgImage = context.makeImage()
        else { return nil }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, type.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    // MARK: - Format detection

    @Test("Known image data is detected from its container type", arguments: knownFormatCases)
    func knownImageDataDetected(_ formatCase: FormatCase) throws {
        let data = try #require(Self.makeImageData(type: formatCase.type))
        let descriptor = try WIImageIO.inspect(data)

        #expect(descriptor.format == formatCase.expected)
    }

    @Test("Empty data cannot produce an inspected format")
    func emptyDataHasNoFormat() {
        #expect(throws: WIImageIO.Error.invalidImageData) {
            try WIImageIO.inspect(Data())
        }
    }

    @Test("Random bytes cannot produce an inspected format")
    func randomBytesHaveNoFormat() {
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x04])

        #expect(throws: WIImageIO.Error.invalidImageData) {
            try WIImageIO.inspect(data)
        }
    }

    // MARK: - isHEIF property

    @Test("isHEIF is true only for .heif")
    func isHEIFFlag() {
        #expect(WIImageFormat.heif.isHEIF == true)
        #expect(WIImageFormat.jpeg.isHEIF == false)
        #expect(WIImageFormat.png.isHEIF == false)
        #expect(WIImageFormat.unknown.isHEIF == false)
    }
}
