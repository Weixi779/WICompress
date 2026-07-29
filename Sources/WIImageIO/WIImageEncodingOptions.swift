//
//  WIImageEncodingOptions.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

package struct WIImageCopyOptions: Hashable, Sendable {
    package var maximumPixelSize: Int?
    package var compressionQuality: Double?

    package init(
        maximumPixelSize: Int? = nil,
        compressionQuality: Double? = nil
    ) {
        self.maximumPixelSize = maximumPixelSize
        self.compressionQuality = compressionQuality
    }
}

package struct WIImageEncodeOptions: Hashable, Sendable {
    package var compressionQuality: Double?

    package init(compressionQuality: Double? = nil) {
        self.compressionQuality = compressionQuality
    }
}
