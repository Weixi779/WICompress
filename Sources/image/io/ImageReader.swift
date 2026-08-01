//
//  ImageReader.swift
//  WIImageIO
//
//  Created by weixi on 2026/8/1.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import ImageIO
@_exported public import WIImageDomain

/// The entry point for inspecting and processing encoded image data.
public final class ImageReader {
    let source: CGImageSource

    public let descriptor: ImageDescriptor

    init(
        source: CGImageSource,
        descriptor: ImageDescriptor
    ) {
        self.source = source
        self.descriptor = descriptor
    }
}
