//
//  WIImageDecodingOptions.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

package struct WIImageDecodeOptions: Hashable, Sendable {
    package var cacheImmediately: Bool

    package init(cacheImmediately: Bool = true) {
        self.cacheImmediately = cacheImmediately
    }
}

package struct WIThumbnailOptions: Hashable, Sendable {
    package var maximumPixelSize: Int?
    package var appliesOrientationTransform: Bool
    package var cacheImmediately: Bool

    package init(
        maximumPixelSize: Int? = nil,
        appliesOrientationTransform: Bool = true,
        cacheImmediately: Bool = true
    ) {
        self.maximumPixelSize = maximumPixelSize
        self.appliesOrientationTransform = appliesOrientationTransform
        self.cacheImmediately = cacheImmediately
    }
}
