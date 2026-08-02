//
//  WICompressDataCharacterizationTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import Testing
import WICompress
@testable import WICompressDomain
@testable import WIImageDomain

@Suite("WICompress Data Characterization", .tags(.imageIOCore, .compression))
struct WICompressDataCharacterizationTests {
    struct Fixture: CustomTestStringConvertible, Sendable {
        let url: URL

        var testDescription: String {
            url.lastPathComponent
        }
    }

    private struct ImageInfo {
        let width: Int
        let height: Int
        let orientation: Int

        var displayWidth: Int {
            swapsDimensions ? height : width
        }

        var displayHeight: Int {
            swapsDimensions ? width : height
        }

        private var swapsDimensions: Bool {
            [5, 6, 7, 8].contains(orientation)
        }
    }

    static var fixtures: [Fixture] {
        ["jpg", "jpeg", "png", "heic", "heif"]
            .flatMap { Bundle.module.urls(forResourcesWithExtension: $0, subdirectory: "Resources") ?? [] }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map(Fixture.init(url:))
    }

    @Test("Resources fixtures are discoverable for Process Data API")
    func fixturesAreDiscoverable() {
        #expect(!Self.fixtures.isEmpty)
    }

    @Test("Process Data API preserves format and display-size contract", arguments: fixtures)
    func processDataAPIContract(_ fixture: Fixture) throws {
        let inputData = try Data(contentsOf: fixture.url)
        let inputInfo = try Self.imageInfo(inputData)

        let outputData = try WICompressor.process(inputData).data
        let outputInfo = try Self.imageInfo(outputData)

        let expectedSize = try WIImageResize.lubanV2.targetSize(
            for: WIPixelSize(
                width: inputInfo.displayWidth,
                height: inputInfo.displayHeight
            )
        )

        #expect(try imageFormat(of: outputData) == imageFormat(of: inputData))
        #expect(abs(outputInfo.displayWidth - expectedSize.width) <= 1)
        #expect(abs(outputInfo.displayHeight - expectedSize.height) <= 1)
    }

    private static func imageInfo(_ data: Data) throws -> ImageInfo {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try #require(properties.intValue(for: kCGImagePropertyPixelWidth))
        let height = try #require(properties.intValue(for: kCGImagePropertyPixelHeight))
        let orientation = properties.intValue(for: kCGImagePropertyOrientation) ?? 1

        return ImageInfo(width: width, height: height, orientation: orientation)
    }
}
