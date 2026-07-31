//
//  WICompressorPublicSurfaceTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import Testing
import WICompress

@Suite("WICompressor Public Surface", .tags(.publicAPI))
struct WICompressorPublicSurfaceTests {

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
            target: WICompressionTarget(
                maxBytes: 1024,
                sizing: WICompressionSizing(maximumPixelSize: 0)
            ),
            testDescription: "zero maximum pixel size"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                sizing: WICompressionSizing(maximumPixelSize: -1)
            ),
            testDescription: "negative maximum pixel size"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                sizing: WICompressionSizing(
                    aspectRatio: WIAspectRatio(width: 0, height: 1)
                )
            ),
            testDescription: "zero aspect-ratio width"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                sizing: WICompressionSizing(
                    aspectRatio: WIAspectRatio(width: 1, height: .nan)
                )
            ),
            testDescription: "non-finite aspect-ratio height"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                sizing: WICompressionSizing(
                    aspectRatio: WIAspectRatio(width: 1, height: 1),
                    anchor: WICropAnchor(x: -0.1, y: 0.5)
                )
            ),
            testDescription: "anchor before the left edge"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                sizing: WICompressionSizing(
                    aspectRatio: WIAspectRatio(width: 1, height: 1),
                    anchor: WICropAnchor(x: 0.5, y: 1.1)
                )
            ),
            testDescription: "anchor after the bottom edge"
        ),
        InvalidTargetCase(
            target: WICompressionTarget(
                maxBytes: 1024,
                sizing: WICompressionSizing(
                    anchor: WICropAnchor(x: 0, y: 0)
                )
            ),
            testDescription: "anchor without an aspect ratio"
        ),
    ]

    private static func tinyPNGData() throws -> Data {
        try resourceData("synthetic_tiny_1x1", extension: "png")
    }

    private static func resourceData(_ name: String, extension ext: String) throws -> Data {
        try Data(contentsOf: resourceURL(name, extension: ext))
    }

    private static func resourceURL(_ name: String, extension ext: String) throws -> URL {
        try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Resources"
            )
        )
    }

    @Test("Default target values match target-compression defaults")
    func defaultTarget() {
        let target = WICompressionTarget(maxBytes: 1024)

        #expect(target.maxBytes == 1024)
        #expect(target.sizing == WICompressionSizing())
        #expect(
            target.output == WIImageOutput(
                representation: .pngIfAlphaOtherwiseJPEG,
                metadata: .strip,
                colorSpace: .convert(to: .sRGB)
            )
        )
    }

    @Test("No-op Process returns the original data")
    func noOpProcessReturnsOriginalData() throws {
        let input = try Self.tinyPNGData()
        let result = try WICompressor.process(
            input,
            using: WIImageProcess(
                sizing: .original,
                quality: nil,
                output: WIImageOutput(
                    representation: .preserve,
                    metadata: .preserve,
                    colorSpace: .preserve
                )
            )
        )

        #expect(result.data == input)
        #expect(result.format == .png)
        #expect(result.pixelSize == WIPixelSize(width: 1, height: 1))
        #expect(result.byteCount == input.count)
    }

    @Test("Preserve target can return original data")
    func preserveTargetReturnsOriginalData() throws {
        let input = try Self.tinyPNGData()
        let result = try WICompressor.compress(
            input,
            to: WICompressionTarget(
                maxBytes: input.count,
                output: WIImageOutput(
                    representation: .preserve,
                    metadata: .preserve,
                    colorSpace: .preserve
                )
            )
        )

        #expect(result.data == input)
        #expect(result.format == .png)
        #expect(result.pixelSize == WIPixelSize(width: 1, height: 1))
        #expect(result.byteCount == input.count)
    }

    @Test("Preserve target reports oriented display size when returning original data")
    func preserveTargetResultUsesDisplaySizeForOrientedOriginal() throws {
        let input = try Self.resourceData("real_heic_4032x3024_o6_gps_hdr", extension: "heic")
        let result = try WICompressor.compress(
            input,
            to: WICompressionTarget(
                maxBytes: input.count,
                output: WIImageOutput(
                    representation: .preserve,
                    metadata: .preserve,
                    colorSpace: .preserve
                )
            )
        )

        #expect(result.data == input)
        #expect(result.format == .heif)
        #expect(result.pixelSize == WIPixelSize(width: 3024, height: 4032))
        #expect(result.byteCount == input.count)
    }

    @Test("Data and file Target terminals have equivalent behavior")
    func dataAndFileTargetTerminalsAreEquivalent() throws {
        let url = try Self.resourceURL("real_jpeg_2098x1350_landscape", extension: "jpg")
        let data = try Data(contentsOf: url)
        let target = WICompressionTarget(
            maxBytes: 64 * 1024,
            sizing: WICompressionSizing(
                maximumPixelSize: 320,
                aspectRatio: WIAspectRatio(width: 1, height: 1)
            )
        )

        let dataResult = try WICompressor.compress(data, to: target)
        let fileResult = try WICompressor.compress(contentsOf: url, to: target)

        #expect(fileResult.data == dataResult.data)
        #expect(fileResult.format == dataResult.format)
        #expect(fileResult.pixelSize == dataResult.pixelSize)
        #expect(fileResult.byteCount == dataResult.byteCount)
    }

    @Test("Invalid input data throws explicit WICompressError", arguments: invalidInputCases)
    func invalidInputDataThrowsExplicitError(_ invalidInputCase: InvalidInputCase) throws {
        let data = try Self.data(for: invalidInputCase)

        #expect(throws: invalidInputCase.expectedError) {
            _ = try WICompressor.process(data)
        }
    }

    @Test("Invalid target values throw invalidTarget", arguments: invalidTargetCases)
    func invalidTargetValuesThrowInvalidTarget(_ invalidTargetCase: InvalidTargetCase) throws {
        let data = try Self.tinyPNGData()

        #expect(throws: WICompressError.invalidTarget) {
            _ = try WICompressor.compress(data, to: invalidTargetCase.target)
        }
    }

    @Test("Target validation precedes file source creation")
    func targetValidationPrecedesFileSourceCreation() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wi-compress-missing-\(UUID().uuidString)")

        #expect(throws: WICompressError.invalidTarget) {
            _ = try WICompressor.compress(
                contentsOf: url,
                to: WICompressionTarget(maxBytes: 0)
            )
        }
    }

    @Test("Process validation precedes file source creation")
    func processValidationPrecedesFileSourceCreation() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wi-process-missing-\(UUID().uuidString)")

        #expect(throws: WICompressError.invalidCrop) {
            _ = try WICompressor.process(
                contentsOf: url,
                using: WIImageProcess(
                    crop: .aspectRatio(width: 0, height: 1)
                )
            )
        }
    }

    @Test("Target JPEG requires an opaque custom background")
    func targetJPEGRequiresOpaqueCustomBackground() throws {
        let data = try Self.tinyPNGData()
        let target = WICompressionTarget(
            maxBytes: 1024,
            output: WIImageOutput(
                representation: .jpeg(
                    background: .color(
                        WIColor(
                            red: 1,
                            green: 1,
                            blue: 1,
                            alpha: 0.5
                        )
                    )
                )
            )
        )

        #expect(throws: WICompressError.nonOpaqueJPEGBackground) {
            _ = try WICompressor.compress(data, to: target)
        }
    }

    @Test("Target compression fails rather than returning bytes over the target")
    func targetCompressionFailsWhenOutputExceedsMaxBytes() throws {
        let input = try Self.tinyPNGData()
        let target = WICompressionTarget(
            maxBytes: 1,
            output: WIImageOutput(
                representation: .preserve,
                metadata: .preserve,
                colorSpace: .preserve
            )
        )

        do {
            _ = try WICompressor.compress(input, to: target)
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
            _ = try WICompressor.process(contentsOf: url)
        }
    }

    @Test("Target URL read failures are exposed as WICompressError.fileReadFailed")
    func targetURLReadFailureThrowsFileReadFailed() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wi-compress-missing-\(UUID().uuidString)")

        #expect(throws: WICompressError.fileReadFailed(url)) {
            _ = try WICompressor.compress(contentsOf: url, to: WICompressionTarget(maxBytes: 1024))
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
