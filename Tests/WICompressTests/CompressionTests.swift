#if os(iOS)
import Foundation
import Testing
import UIKit
@testable import WICompress

@Suite("WICompress Compression", .tags(.compression))
struct CompressionTests {

    // MARK: - Helpers

    /// Synthetic 3000×2000 solid-color image — large enough for Luban to apply ratio = 2.
    private func makeLargeImage() -> (image: UIImage, data: Data) {
        let size = CGSize(width: 3000, height: 2000)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let data = image.jpegData(compressionQuality: 1.0)!
        return (image, data)
    }

    /// Synthetic 500×400 solid-color image — small enough that Luban returns ratio = 1.
    private func makeSmallImage() -> UIImage {
        let size = CGSize(width: 500, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.systemRed.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - compressImage

    @Test("compressImage returns non-nil for JPEG input")
    func compressReturnsData() {
        let (image, formatData) = makeLargeImage()
        let result = WICompress.compressImage(image, quality: 0.6, formatData: formatData)
        #expect(result != nil)
    }

    @Test("compressImage output is smaller than lossless input")
    func compressReducesSize() throws {
        let (image, losslessData) = makeLargeImage()
        let result = try #require(WICompress.compressImage(image, quality: 0.6, formatData: losslessData))
        #expect(result.count < losslessData.count)
    }

    @Test("compressImage preserves JPEG format")
    func compressPreservesJPEGFormat() throws {
        let (image, formatData) = makeLargeImage()
        let result = try #require(WICompress.compressImage(image, quality: 0.6, formatData: formatData))
        #expect(WIImageFormat(data: result) == .jpeg)
    }

    @Test("lower quality produces smaller output than higher quality", .tags(.edgeCase))
    func qualityAffectsOutputSize() throws {
        let (image, formatData) = makeLargeImage()
        let lowQuality = try #require(WICompress.compressImage(image, quality: 0.1, formatData: formatData))
        let highQuality = try #require(WICompress.compressImage(image, quality: 0.9, formatData: formatData))
        #expect(lowQuality.count < highQuality.count)
    }

    // MARK: - resizeImage

    @Suite("resizeImage", .tags(.compression, .luban))
    struct ResizeTests {

        @Test("large image dimensions are reduced")
        func largeImageIsResized() {
            let size = CGSize(width: 3000, height: 2000)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                UIColor.systemBlue.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            let result = WICompress.resizeImage(image)
            #expect(result.size.width < 3000)
            #expect(result.size.height < 2000)
        }

        @Test("small image dimensions are unchanged")
        func smallImageUnchanged() {
            let size = CGSize(width: 500, height: 400)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                UIColor.systemRed.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            let result = WICompress.resizeImage(image)
            #expect(result.size.width == 500)
            #expect(result.size.height == 400)
        }
    }
}
#endif
