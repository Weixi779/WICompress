import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WICompress

@Suite("WIImageFormat Detection", .tags(.format))
struct WIImageFormatTests {

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

    @Test("JPEG data is detected as .jpeg")
    func jpegDataDetected() throws {
        let data = try #require(Self.makeImageData(type: .jpeg))
        #expect(WIImageFormat(data: data) == .jpeg)
    }

    @Test("PNG data is detected as .png")
    func pngDataDetected() throws {
        let data = try #require(Self.makeImageData(type: .png))
        #expect(WIImageFormat(data: data) == .png)
    }

    @Test("Empty data returns .unknown", .tags(.edgeCase))
    func emptyDataReturnsUnknown() {
        #expect(WIImageFormat(data: Data()) == .unknown)
    }

    @Test("Random bytes return .unknown", .tags(.edgeCase))
    func randomBytesReturnUnknown() {
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        #expect(WIImageFormat(data: data) == .unknown)
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
