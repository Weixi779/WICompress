//
//  WICompressPublicSurfaceTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import Testing
@testable import WICompress

@Suite("WICompress Public Surface", .tags(.publicAPI))
struct WICompressPublicSurfaceTests {

    struct InvalidInputCase: CustomTestStringConvertible, Sendable {
        enum Payload: Sendable {
            case empty
            case randomBytes
            case truncatedJPEGPrefix(Int)
        }

        let payload: Payload
        let expectedError: WICompressError
        let testDescription: String
    }

    struct InvalidTargetCase: CustomTestStringConvertible, Sendable {
        let target: WICompressionTarget
        let testDescription: String
    }

    static let invalidInputCases: [InvalidInputCase] = [
        InvalidInputCase(
            payload: .empty,
            expectedError: .invalidImageData,
            testDescription: "empty data"
        ),
        InvalidInputCase(
            payload: .randomBytes,
            expectedError: .invalidImageData,
            testDescription: "random bytes"
        ),
        InvalidInputCase(
            payload: .truncatedJPEGPrefix(8),
            expectedError: .invalidImageData,
            testDescription: "truncated JPEG prefix"
        ),
    ]

    static let invalidTargetCases: [InvalidTargetCase] = [
        InvalidTargetCase(
            target: WICompressionTarget(maxBytes: 0),
            testDescription: "zero byte target"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(maxBytes: 1024, geometry: .fit(maxLongSide: 0)),
            testDescription: "zero max long side"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                geometry: .fitInside(box: WISize(width: .nan, height: 100))
            ),
            testDescription: "non-finite fit box"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                geometry: .fill(size: WISize(width: 0, height: 100))
            ),
            testDescription: "zero fill width"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                geometry: .exactCanvas(
                    size: WISize(width: 100, height: -1),
                    background: WIColor(red: 1, green: 1, blue: 1)
                )
            ),
            testDescription: "negative canvas height"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                geometry: .fill(
                    size: WISize(width: Double(Int.max) * 2, height: 100)
                )
            ),
            testDescription: "unrepresentable pixel width"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                geometry: .fill(
                    size: WISize(width: Double(Int.max), height: 100)
                )
            ),
            testDescription: "pixel width at the Int.max rounding boundary"
        ),
    ]

    private static func tinyPNGData() throws -> Data {
        try resourceData("synthetic_tiny_1x1", extension: "png")
    }

    private static func resourceData(_ name: String, extension ext: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Resources"
            )
        )
        return try Data(contentsOf: url)
    }

    @Test("Default options match the documented upload-compression defaults")
    func defaultOptions() {
        #expect(WICompressOptions.default == WICompressOptions())
        #expect(WICompressOptions.default.resize == .luban)
        #expect(WICompressOptions.default.format == .preserve)
        #expect(WICompressOptions.default.metadata == .strip)
        #expect(WICompressOptions.default.quality == .compression(0.6))
        #expect(WICompressOptions.default.colorSpace == .preserve)
    }

    @Test("Default target values match target-compression defaults")
    func defaultTarget() {
        let target = WICompressionTarget(maxBytes: 1024)

        #expect(target.maxBytes == 1024)
        #expect(target.geometry == .original)
        #expect(target.output == .upload)
        #expect(target.preference == .balanced)
        #expect(WICompressionOutput.upload == WICompressionOutput())
        #expect(
            WICompressionOutput.preserve == WICompressionOutput(
                format: .preserve,
                metadata: .preserve,
                colorSpace: .preserve
            )
        )
    }

    @Test("No-op policy returns the original data")
    func noOpPolicyReturnsOriginalData() throws {
        let input = try Self.tinyPNGData()
        let output = try WICompress.compress(
            input,
            options: WICompressOptions(
                resize: .none,
                format: .preserve,
                metadata: .preserve,
                quality: .none
            )
        )

        #expect(output == input)
    }

    @Test("Preserve target can return original data")
    func preserveTargetReturnsOriginalData() throws {
        let input = try Self.tinyPNGData()
        let result = try WICompress.compress(
            input,
            to: WICompressionTarget(
                maxBytes: input.count,
                output: .preserve
            )
        )

        #expect(result.data == input)
        #expect(result.format == .png)
        #expect(result.pixelSize == WISize(width: 1, height: 1))
        #expect(result.byteCount == input.count)
    }

    @Test("Preserve target reports oriented display size when returning original data")
    func preserveTargetResultUsesDisplaySizeForOrientedOriginal() throws {
        let input = try Self.resourceData("real_heic_4032x3024_o6_gps_hdr", extension: "heic")
        let result = try WICompress.compress(
            input,
            to: WICompressionTarget(
                maxBytes: input.count,
                output: .preserve
            )
        )

        #expect(result.data == input)
        #expect(result.format == .heif)
        #expect(result.pixelSize == WISize(width: 3024, height: 4032))
        #expect(result.byteCount == input.count)
    }

    @Test("Invalid input data throws explicit WICompressError", arguments: invalidInputCases)
    func invalidInputDataThrowsExplicitError(_ invalidInputCase: InvalidInputCase) throws {
        let data = try Self.data(for: invalidInputCase)

        #expect(throws: invalidInputCase.expectedError) {
            _ = try WICompress.compress(data)
        }
    }

    @Test("Invalid target values throw invalidTarget", arguments: invalidTargetCases)
    func invalidTargetValuesThrowInvalidTarget(_ invalidTargetCase: InvalidTargetCase) throws {
        let data = try Self.tinyPNGData()

        #expect(throws: WICompressError.invalidTarget) {
            _ = try WICompress.compress(data, to: invalidTargetCase.target)
        }
    }

    @Test("Hard HEIF geometry rejects odd dimensions")
    func hardHEIFGeometryRejectsOddDimensions() throws {
        let data = try Self.tinyPNGData()
        let target = WICompressionTarget(
            maxBytes: 1024,
            geometry: .fill(size: WISize(width: 601, height: 420)),
            output: WICompressionOutput(format: .heic)
        )

        #expect(throws: WICompressError.invalidTarget) {
            _ = try WICompress.compress(data, to: target)
        }
    }

    @Test("JPEG exact canvas requires an opaque background")
    func jpegExactCanvasRequiresOpaqueBackground() throws {
        let data = try Self.tinyPNGData()
        let target = WICompressionTarget(
            maxBytes: 1024,
            geometry: .exactCanvas(
                size: WISize(width: 10, height: 10),
                background: WIColor(red: 1, green: 1, blue: 1, alpha: 0.5)
            ),
            output: WICompressionOutput(format: .jpeg(background: .white))
        )

        #expect(throws: WICompressError.nonOpaqueJPEGBackground) {
            _ = try WICompress.compress(data, to: target)
        }
    }

    @Test("Hard geometry target returns fixed pixel size")
    func hardGeometryTargetReturnsFixedPixelSize() throws {
        let data = try Self.tinyPNGData()
        let target = WICompressionTarget(
            maxBytes: 100_000,
            geometry: .fill(size: WISize(width: 10, height: 10))
        )
        let result = try WICompress.compress(data, to: target)

        #expect(result.pixelSize == WISize(width: 10, height: 10))
        #expect(result.byteCount == result.data.count)
    }

    @Test("Target compression fails rather than returning bytes over the target")
    func targetCompressionFailsWhenOutputExceedsMaxBytes() throws {
        let input = try Self.tinyPNGData()
        let target = WICompressionTarget(
            maxBytes: 1,
            output: .preserve
        )

        do {
            _ = try WICompress.compress(input, to: target)
            Issue.record("Expected targetUnsatisfiable")
        } catch WICompressError.targetUnsatisfiable(let smallestByteCount) {
            #expect((smallestByteCount ?? 0) > target.maxBytes)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("URL read failures are exposed as WICompressError.fileReadFailed")
    func urlReadFailureThrowsFileReadFailed() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wi-compress-missing-\(UUID().uuidString)")

        #expect(throws: WICompressError.fileReadFailed(url)) {
            _ = try WICompress.compress(contentsOf: url)
        }
    }

    @Test("Target URL read failures are exposed as WICompressError.fileReadFailed")
    func targetURLReadFailureThrowsFileReadFailed() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wi-compress-missing-\(UUID().uuidString)")

        #expect(throws: WICompressError.fileReadFailed(url)) {
            _ = try WICompress.compress(contentsOf: url, to: WICompressionTarget(maxBytes: 1024))
        }
    }

    private static func data(for invalidInputCase: InvalidInputCase) throws -> Data {
        switch invalidInputCase.payload {
        case .empty:
            return Data()
        case .randomBytes:
            return Data([0x00, 0x01, 0x02, 0x03, 0x04])
        case .truncatedJPEGPrefix(let byteCount):
            let data = try Self.resourceData("real_jpeg_2098x1350_landscape", extension: "jpg")
            return Data(data.prefix(byteCount))
        }
    }
}
