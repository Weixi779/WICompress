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
        let url = try #require(
            Bundle.module.url(
                forResource: "synthetic_tiny_1x1",
                withExtension: "png",
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

    @Test("Invalid input data throws explicit WICompressError", arguments: invalidInputCases)
    func invalidInputDataThrowsExplicitError(_ invalidInputCase: InvalidInputCase) throws {
        let data = try Self.data(for: invalidInputCase)

        #expect(throws: invalidInputCase.expectedError) {
            _ = try WICompress.compress(data)
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

    private static func data(for invalidInputCase: InvalidInputCase) throws -> Data {
        switch invalidInputCase.payload {
        case .empty:
            return Data()
        case .randomBytes:
            return Data([0x00, 0x01, 0x02, 0x03, 0x04])
        case .truncatedJPEGPrefix(let byteCount):
            let url = try #require(
                Bundle.module.url(
                    forResource: "real_jpeg_2098x1350_landscape",
                    withExtension: "jpg",
                    subdirectory: "Resources"
                )
            )
            let data = try Data(contentsOf: url)
            return Data(data.prefix(byteCount))
        }
    }
}
