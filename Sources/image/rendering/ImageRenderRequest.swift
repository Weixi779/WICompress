//
//  ImageRenderRequest.swift
//  WIImageRendering
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import WIImageDomain

/// Alpha storage behavior for the destination bitmap surface.
package enum ImageAlphaMode: Sendable, Equatable {
    case preserve
    case opaque
}

/// Color-space behavior for one rendering operation.
package enum ImageRenderColorSpace: Sendable, Equatable {
    case source
    case convert(WIColorSpace)

    package static var sRGB: Self {
        .convert(.sRGB)
    }
}

/// Resolved pixel facts for one rendering operation.
package struct ImageRenderRequest: Sendable, Equatable {
    package let canvasSize: WIPixelSize
    package let sourceRect: Rect
    package let destinationRect: Rect
    package let orientation: WIImageOrientation
    package let alphaMode: ImageAlphaMode
    package let canvasBackground: WIColor?
    package let imageBackground: WIColor?
    package let colorSpace: ImageRenderColorSpace

    package init(
        canvasSize: WIPixelSize,
        sourceRect: Rect,
        destinationRect: Rect,
        orientation: WIImageOrientation = .up,
        alphaMode: ImageAlphaMode = .preserve,
        canvasBackground: WIColor? = nil,
        imageBackground: WIColor? = nil,
        colorSpace: ImageRenderColorSpace = .source
    ) {
        self.canvasSize = canvasSize
        self.sourceRect = sourceRect
        self.destinationRect = destinationRect
        self.orientation = orientation
        self.alphaMode = alphaMode
        self.canvasBackground = canvasBackground
        self.imageBackground = imageBackground
        self.colorSpace = colorSpace
    }
}
