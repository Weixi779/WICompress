//
//  DecodingOptions.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

extension WIImageIO {
    /// Pixel decoding behavior for a full image frame.
    public struct DecodeOptions: Hashable, Sendable {
        public let cacheImmediately: Bool

        public init(cacheImmediately: Bool = true) {
            self.cacheImmediately = cacheImmediately
        }
    }

    /// ImageIO thumbnail decoding behavior.
    public struct ThumbnailOptions: Hashable, Sendable {
        public let maximumPixelSize: Int?
        public let appliesOrientationTransform: Bool
        public let cacheImmediately: Bool

        public init(
            maximumPixelSize: Int? = nil,
            appliesOrientationTransform: Bool = true,
            cacheImmediately: Bool = true
        ) {
            self.maximumPixelSize = maximumPixelSize.map { max(1, $0) }
            self.appliesOrientationTransform = appliesOrientationTransform
            self.cacheImmediately = cacheImmediately
        }
    }
}
