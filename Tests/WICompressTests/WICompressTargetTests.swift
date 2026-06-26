//
//  WICompressTargetTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/6/24.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import Testing
@testable import WICompress

@Suite("WICompress Target Compression", .tags(.compression, .imageIOCore, .publicAPI))
struct WICompressTargetTests {
    private struct ImageInfo {
        let width: Int
        let height: Int
        let orientation: Int
        let hasGPS: Bool
        let hasAlpha: Bool?

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

    @Test("Invalid target values throw before compression")
    func invalidTargetValuesThrow() throws {
        let inputData = try Self.resourceData("synthetic_tiny_1x1", extension: "png")

        #expect(throws: WICompressError.invalidCompressionTarget) {
            _ = try WICompress.compress(
                inputData,
                to: WICompressionTarget(maxBytes: 0)
            )
        }

        #expect(throws: WICompressError.invalidCompressionTarget) {
            _ = try WICompress.compress(
                inputData,
                to: WICompressionTarget(maxBytes: 1024, maxLongSide: 0)
            )
        }
    }

    @Test("JPEG target respects maxBytes and maxLongSide")
    func jpegTargetRespectsLimits() throws {
        let inputData = try Self.resourceData("real_jpeg_2098x1350_landscape", extension: "jpg")

        let outputData = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                maxLongSide: 512,
                format: .preserve,
                metadata: .strip
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(outputData.count <= 100_000)
        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) <= 512)
    }

    @Test("Small JPEG target can reduce dimensions after quality search")
    func smallJPEGTargetUsesSearch() throws {
        let inputData = try Self.resourceData("real_jpeg_2098x1350_landscape", extension: "jpg")

        let outputData = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 20_000,
                maxLongSide: 1_200,
                format: .preserve,
                metadata: .strip
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(outputData.count <= 20_000)
        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) <= 1_200)
    }

    @Test("Transparent PNG target requires a JPEG background")
    func transparentPNGRequiresJPEGBackground() throws {
        let inputData = try Self.resourceData("real_png_1086x1630_alpha", extension: "png")

        #expect(throws: WICompressError.transparentSourceRequiresBackground(.png)) {
            _ = try WICompress.compress(
                inputData,
                to: WICompressionTarget(
                    maxBytes: 200_000,
                    maxLongSide: 512,
                    format: .jpeg(background: .disallow),
                    metadata: .strip
                )
            )
        }
    }

    @Test("Transparent PNG target can flatten to JPEG")
    func transparentPNGFlattensToJPEGTarget() throws {
        let inputData = try Self.resourceData("real_png_1086x1630_alpha", extension: "png")

        let outputData = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 200_000,
                maxLongSide: 512,
                format: .jpeg(background: .white),
                metadata: .strip
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(outputData.count <= 200_000)
        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(outputInfo.hasAlpha != true)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) <= 512)
    }

    @Test("PNG target preserves PNG format")
    func pngTargetPreservesFormat() throws {
        let inputData = try Self.resourceData("real_png_1928x464_pano", extension: "png")

        let outputData = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 50_000,
                maxLongSide: 500,
                format: .preserve,
                metadata: .strip
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(outputData.count <= 50_000)
        #expect(WIImageFormat(data: outputData) == .png)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) <= 500)
    }

    @Test("Impossible target throws targetBytesUnreachable")
    func impossibleTargetThrows() throws {
        let inputData = try Self.resourceData("synthetic_tiny_1x1", extension: "png")

        let error = try #require(throws: WICompressError.self) {
            _ = try WICompress.compress(
                inputData,
                to: WICompressionTarget(
                    maxBytes: 1,
                    format: .preserve,
                    metadata: .preserve
                )
            )
        }

        guard case .targetBytesUnreachable(let maxBytes, let bestByteCount) = error else {
            Issue.record("Expected targetBytesUnreachable")
            return
        }

        let unwrappedBestByteCount = try #require(bestByteCount)
        #expect(maxBytes == 1)
        #expect(unwrappedBestByteCount > 1)
    }

    @Test("Target preserve policies may return the original data")
    func targetPreservePoliciesMayReturnOriginal() throws {
        let inputData = try Self.resourceData("synthetic_tiny_1x1", extension: "png")

        let outputData = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: inputData.count + 1,
                format: .preserve,
                metadata: .preserve
            )
        )

        #expect(outputData == inputData)
    }

    @Test("Target metadata strip does not return metadata-bearing original")
    func targetMetadataStripDoesNotPassthrough() throws {
        let inputData = try Self.resourceData("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.hasGPS == true, "Fixture should contain GPS metadata")

        let outputData = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 5_000_000,
                format: .preserve,
                metadata: .strip
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(outputData.count <= 5_000_000)
        #expect(WIImageFormat(data: outputData) == WIImageFormat(data: inputData))
        #expect(outputInfo.hasGPS == false)
    }

    private static func resourceData(_ name: String, extension ext: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Resources"
            ),
            "Missing fixture: \(name).\(ext)"
        )

        return try Data(contentsOf: url)
    }

    private static func imageInfo(_ data: Data) throws -> ImageInfo {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try #require(properties.intValue(for: kCGImagePropertyPixelWidth))
        let height = try #require(properties.intValue(for: kCGImagePropertyPixelHeight))
        let orientation = properties.intValue(for: kCGImagePropertyOrientation) ?? 1

        return ImageInfo(
            width: width,
            height: height,
            orientation: orientation,
            hasGPS: properties.dictionaryExists(for: kCGImagePropertyGPSDictionary),
            hasAlpha: properties.boolValue(for: kCGImagePropertyHasAlpha)
        )
    }
}
