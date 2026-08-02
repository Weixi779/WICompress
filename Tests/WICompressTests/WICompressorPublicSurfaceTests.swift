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

    private static func tinyPNGData() throws -> Data {
        try resourceData("synthetic_tiny_1x1", extension: "png")
    }

    private static var passthroughProcess: WIImageProcess {
        WIImageProcess(
            sizing: .original,
            quality: nil,
            output: WIImageOutput(
                representation: .preserve,
                metadata: .preserve,
                colorSpace: .preserve
            )
        )
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
    func defaultTarget() throws {
        let target = try WICompressionTarget(maxBytes: 1024)

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
            using: Self.passthroughProcess
        )

        #expect(result.data == input)
        #expect(result.format == .png)
        #expect(result.pixelSize == WIPixelSize(width: 1, height: 1))
        #expect(result.byteCount == input.count)
    }

    @Test("Async Process data and file terminals preserve the synchronous render path")
    func asyncProcessTerminalsPreserveSemantics() async throws {
        let url = try Self.resourceURL("synthetic_tiny_1x1", extension: "png")
        let input = try Data(contentsOf: url)
        let process = WIImageProcess(
            sizing: .resize(
                using: WIImageResize.exact(
                    WIPixelSize(width: 2, height: 2)
                )
            )
        )

        let dataResult = try await WICompressor.process(
            input,
            using: process
        )
        let fileResult = try await WICompressor.process(
            contentsOf: url,
            using: process
        )
        let synchronousResult = try Self.processSynchronously(
            input,
            using: process
        )

        #expect(dataResult.pixelSize == WIPixelSize(width: 2, height: 2))
        Self.expectEquivalentResults(fileResult, dataResult)
        Self.expectEquivalentResults(synchronousResult, dataResult)
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

    @Test("Async Target data and file terminals preserve synchronous search semantics")
    func asyncTargetTerminalsPreserveSemantics() async throws {
        let url = try Self.resourceURL("real_jpeg_2098x1350_landscape", extension: "jpg")
        let input = try Data(contentsOf: url)
        let target = try WICompressionTarget(
            maxBytes: 64 * 1024,
            sizing: WICompressionSizing(
                maximumPixelSize: 320,
                aspectRatio: .square
            )
        )

        let dataResult = try await WICompressor.compress(input, to: target)
        let fileResult = try await WICompressor.compress(
            contentsOf: url,
            to: target
        )
        let synchronousResult = try Self.compressSynchronously(
            input,
            to: target
        )

        #expect(dataResult.byteCount <= target.maxBytes)
        Self.expectEquivalentResults(fileResult, dataResult)
        Self.expectEquivalentResults(synchronousResult, dataResult)
    }

    @Test("Async terminals preserve WICompressError failures")
    func asyncTerminalPreservesCompressionError() async {
        do {
            _ = try await WICompressor.process(Data())
            Issue.record("Expected invalidImageData")
        } catch let error as WICompressError {
            #expect(error == .invalidImageData)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Pre-cancelled async terminals throw CancellationError")
    func preCancelledAsyncTerminalsThrowCancellationError() async throws {
        let input = try Self.tinyPNGData()
        let target = try WICompressionTarget(maxBytes: input.count)

        let processTask = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await WICompressor.process(input)
        }
        processTask.cancel()
        await Self.expectCancellation(from: processTask)

        let targetTask = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await WICompressor.compress(input, to: target)
        }
        targetTask.cancel()
        await Self.expectCancellation(from: targetTask)
    }

    @Test("Synchronous terminals ignore surrounding Task cancellation")
    func synchronousTerminalIgnoresTaskCancellation() async throws {
        let input = try Self.tinyPNGData()
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try Self.processSynchronously(
                input,
                using: Self.passthroughProcess
            )
        }

        task.cancel()
        let result = try await task.value

        #expect(result.data == input)
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
        let target = try WICompressionTarget(
            maxBytes: 64 * 1024,
            sizing: WICompressionSizing(
                maximumPixelSize: 320,
                aspectRatio: .square
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

    @Test("Invalid targets fail during construction")
    func invalidTargetsFailDuringConstruction() {
        #expect(throws: WICompressError.invalidTarget) {
            _ = try WICompressionTarget(maxBytes: 0)
        }
    }

    @Test("Invalid crop ratios fail during construction")
    func invalidCropFailsDuringConstruction() {
        #expect(throws: WICompressError.invalidCrop) {
            _ = try WIAspectRatio(width: 0, height: 1)
        }
    }

    @Test("Target JPEG requires an opaque custom background")
    func targetJPEGRequiresOpaqueCustomBackground() throws {
        let data = try Self.tinyPNGData()
        let target = try WICompressionTarget(
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
        let target = try WICompressionTarget(
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

    private static func expectCancellation(
        from task: Task<WIResult, any Error>
    ) async {
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func expectEquivalentResults(
        _ lhs: WIResult,
        _ rhs: WIResult
    ) {
        #expect(lhs.data == rhs.data)
        #expect(lhs.format == rhs.format)
        #expect(lhs.pixelSize == rhs.pixelSize)
        #expect(lhs.byteCount == rhs.byteCount)
    }

    private static func processSynchronously(
        _ data: Data,
        using process: WIImageProcess
    ) throws(WICompressError) -> WIResult {
        try WICompressor.process(data, using: process)
    }

    private static func compressSynchronously(
        _ data: Data,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try WICompressor.compress(data, to: target)
    }
}
