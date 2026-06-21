import Foundation
import ImageIO
import Testing
@testable import WICompress

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

    @Test("Resources fixtures are discoverable for Data API")
    func fixturesAreDiscoverable() {
        #expect(!Self.fixtures.isEmpty)
    }

    @Test("Data API preserves format and display-size contract", arguments: fixtures)
    func dataAPIContract(_ fixture: Fixture) throws {
        let inputData = try Data(contentsOf: fixture.url)
        let inputInfo = try Self.imageInfo(inputData)

        let outputData = try WICompress.compress(inputData)
        let outputInfo = try Self.imageInfo(outputData)

        let ratio = WIImageUtils.calculateLubanRatio(
            width: inputInfo.displayWidth,
            height: inputInfo.displayHeight
        )
        let expectedWidth = max(inputInfo.displayWidth / ratio, 1)
        let expectedHeight = max(inputInfo.displayHeight / ratio, 1)

        #expect(WIImageFormat(data: outputData) == WIImageFormat(data: inputData))
        #expect(abs(outputInfo.displayWidth - expectedWidth) <= 1)
        #expect(abs(outputInfo.displayHeight - expectedHeight) <= 1)
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
