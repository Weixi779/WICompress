import Foundation
import Testing
@testable import WICompress

@Suite("WICompress Public Surface", .tags(.publicAPI))
struct WICompressPublicSurfaceTests {

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

    @Test("Invalid image data throws invalidImageData")
    func invalidImageDataThrows() {
        #expect(throws: WICompressError.invalidImageData) {
            _ = try WICompress.compress(
                Data([0x01, 0x02, 0x03]),
                options: WICompressOptions(
                    resize: .none,
                    format: .preserve,
                    metadata: .preserve,
                    quality: .none
                )
            )
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
}
