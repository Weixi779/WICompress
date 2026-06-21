#if os(iOS)
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
@testable import WICompress

/// Golden / characterization tests over **real image fixtures** in `Resources/`.
///
/// These pin the *observable contract* of `WICompress.compressImage` —
/// output format and output pixel dimensions — for every image dropped into
/// `Tests/WICompressTests/Resources/`. They are deliberately written against
/// stable invariants (not exact bytes), so they survive the planned
/// UIKit → ImageIO core rewrite and will flag any behavioural drift.
///
/// To extend coverage: drop more images into `Resources/`. They are picked up
/// automatically — no code change required.
@Suite("Characterization (real fixtures)", .tags(.compression))
struct CharacterizationTests {

    // MARK: - Fixture discovery

    /// All image fixtures bundled under `Resources/`, sorted for stable ordering.
    static var fixtures: [URL] {
        let exts = ["jpg", "jpeg", "png", "heic", "heif"]
        return exts
            .flatMap { Bundle.module.urls(forResourcesWithExtension: $0, subdirectory: "Resources") ?? [] }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test("Resources fixtures are bundled and discoverable")
    func fixturesAreBundled() {
        #expect(!Self.fixtures.isEmpty, "No fixtures found — check Package.swift resources(.copy) and Resources/ contents")
    }

    // MARK: - Helpers

    /// Encoded pixel size + EXIF orientation read straight from `Data` via ImageIO (no UIKit).
    private static func imageInfo(_ data: Data) -> (width: Int, height: Int, orientation: Int)? {
        guard
            let src = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
            let w = props[kCGImagePropertyPixelWidth] as? Int,
            let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        return (w, h, orientation)
    }

    /// Display-oriented dimensions: EXIF orientations 5–8 swap width/height,
    /// mirroring how `UIImage(data:)` reports `.size`.
    private static func displayDimensions(_ info: (width: Int, height: Int, orientation: Int)) -> (Int, Int) {
        [5, 6, 7, 8].contains(info.orientation) ? (info.height, info.width) : (info.width, info.height)
    }

    // MARK: - Contract: format + dimensions

    @Test("Output format and dimensions match the resize contract", arguments: fixtures)
    func contract(for url: URL) throws {
        let inputData = try Data(contentsOf: url)
        let image = try #require(UIImage(data: inputData), "Could not decode fixture: \(url.lastPathComponent)")
        let inputInfo = try #require(Self.imageInfo(inputData), "No ImageIO metadata for: \(url.lastPathComponent)")

        let result = try #require(
            WICompress.compressImage(image, quality: 0.6, formatData: inputData),
            "compressImage returned nil for: \(url.lastPathComponent)"
        )

        // 1) Format is preserved (heic input maps to the .heif case).
        let inputFormat = WIImageFormat(data: inputData)
        let outputFormat = WIImageFormat(data: result)
        #expect(outputFormat == inputFormat, "format drift on \(url.lastPathComponent): \(inputFormat) -> \(outputFormat)")

        // 2) Output pixel dimensions equal the Luban resize applied to display dims.
        let (displayW, displayH) = Self.displayDimensions(inputInfo)
        let ratio = WIImageUtils.calculateLubanRatio(width: displayW, height: displayH)
        let expectedW = max(displayW / ratio, 1)
        let expectedH = max(displayH / ratio, 1)

        let outputInfo = try #require(Self.imageInfo(result), "Output not decodable for: \(url.lastPathComponent)")
        #expect(outputInfo.width == expectedW, "width drift on \(url.lastPathComponent): got \(outputInfo.width), expected \(expectedW)")
        #expect(outputInfo.height == expectedH, "height drift on \(url.lastPathComponent): got \(outputInfo.height), expected \(expectedH)")

        // Baseline snapshot — visible in test logs for freezing once real photos land.
        print("[baseline] \(url.lastPathComponent): in \(inputInfo.width)x\(inputInfo.height) o\(inputInfo.orientation) \(inputData.count)B -> out \(outputInfo.width)x\(outputInfo.height) \(outputFormat) \(result.count)B")
    }
}
#endif
