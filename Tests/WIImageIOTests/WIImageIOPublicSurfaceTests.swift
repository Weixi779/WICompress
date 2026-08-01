//
//  WIImageIOPublicSurfaceTests.swift
//  WIImageIOTests
//
//  Created by weixi on 2026/8/1.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Testing
import WIImageIO

@Suite("WIImageIO Public Surface")
struct WIImageIOPublicSurfaceTests {
    @Test("Standalone import exposes canonical Image Domain values")
    func standaloneImport() {
        let size = WIPixelSize(width: 12, height: 8)
        let options = ImageThumbnailOptions(maximumPixelSize: 8)

        #expect(size.width == 12)
        #expect(options.maximumPixelSize == 8)
        _ = ImageReader.canDecode(.jpeg)
        _ = ImageReader.canEncode(.png)
    }

    @Test("ImageIO options normalize numeric boundaries")
    func optionNormalization() {
        let thumbnail = ImageThumbnailOptions(maximumPixelSize: 0)
        let transcode = ImageTranscodeOptions(
            maximumPixelSize: -1,
            compressionQuality: 2
        )
        let lowQuality = ImageEncodeOptions(compressionQuality: -1)
        let invalidQuality = ImageEncodeOptions(compressionQuality: .nan)

        #expect(thumbnail.maximumPixelSize == 1)
        #expect(transcode.maximumPixelSize == 1)
        #expect(transcode.compressionQuality == 1)
        #expect(lowQuality.compressionQuality == 0)
        #expect(invalidQuality.compressionQuality == nil)
    }
}
