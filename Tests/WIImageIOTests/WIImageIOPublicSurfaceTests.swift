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
    @Test("Standalone import exposes scoped values and inferred UTTypes")
    func standaloneImport() {
        let size = WIImageIO.PixelSize(width: 12, height: 8)
        let options = WIImageIO.ThumbnailOptions(maximumPixelSize: 8)

        #expect(size.width == 12)
        #expect(options.maximumPixelSize == 8)
        _ = WIImageIO.canDecode(.jpeg)
        _ = WIImageIO.canEncode(.png)
    }
}
