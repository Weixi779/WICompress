//
//  EncodingOptions.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import WIImageDomain

package struct CopyOptions: Hashable, Sendable {
    package var maximumPixelSize: Int?
    package var compressionQuality: Double?
    package var metadata: WIImageMetadataOptions

    package init(
        maximumPixelSize: Int? = nil,
        compressionQuality: Double? = nil,
        metadata: WIImageMetadataOptions = .preserve
    ) {
        self.maximumPixelSize = maximumPixelSize
        self.compressionQuality = compressionQuality
        self.metadata = metadata
    }
}

package struct EncodeOptions: Hashable, Sendable {
    package var compressionQuality: Double?
    package var metadata: WIImageMetadataOptions

    package init(
        compressionQuality: Double? = nil,
        metadata: WIImageMetadataOptions = .strip
    ) {
        self.compressionQuality = compressionQuality
        self.metadata = metadata
    }
}
