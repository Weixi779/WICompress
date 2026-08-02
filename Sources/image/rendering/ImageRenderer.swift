//
//  ImageRenderer.swift
//  WIImageRendering
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import WIImageDomain

/// Renders one source image into a resolved bitmap surface.
package enum ImageRenderer {
    /// Produces an orientation-baked image from concrete rendering facts.
    package static func render(
        _ sourceImage: CGImage,
        request: ImageRenderRequest
    ) throws(ImageRenderingError) -> CGImage {
        try request.validate(sourceImage: sourceImage)

        let colorSpace = try request.colorSpace.resolve(sourceImage.colorSpace)
        let canvas = try BitmapCanvas(
            size: request.canvasSize,
            alphaMode: request.alphaMode,
            colorSpace: colorSpace
        )

        if let canvasBackground = request.canvasBackground {
            try canvas.fill(canvasBackground)
        }
        if let imageBackground = request.imageBackground {
            try canvas.fill(
                imageBackground,
                in: request.destinationRect
            )
        }
        try canvas.draw(
            sourceImage,
            sourceRect: request.sourceRect,
            destinationRect: request.destinationRect,
            orientation: request.orientation
        )
        return try canvas.image()
    }
}

private extension ImageRenderRequest {
    func validate(sourceImage: CGImage) throws(ImageRenderingError) {
        guard sourceRect.isFiniteAndPositive else {
            throw .invalidSourceRect
        }
        guard destinationRect.isFiniteAndPositive else {
            throw .invalidDestinationRect
        }

        let storedPixelSize = WIPixelSize(
            validWidth: sourceImage.width,
            height: sourceImage.height
        )
        let orientedPixelSize = storedPixelSize.oriented(by: orientation)
        guard
            sourceRect.x >= 0,
            sourceRect.y >= 0,
            sourceRect.x + sourceRect.width <= Double(orientedPixelSize.width),
            sourceRect.y + sourceRect.height <= Double(orientedPixelSize.height)
        else {
            throw .sourceRectOutOfBounds
        }

        try validate(background: canvasBackground)
        try validate(background: imageBackground)
    }

    func validate(background: WIColor?) throws(ImageRenderingError) {
        guard let background else {
            return
        }
        guard background.alpha.isFinite, background.alpha >= 1 else {
            throw .nonOpaqueBackground
        }
    }
}

private extension ImageRenderColorSpace {
    func resolve(_ source: CGColorSpace?) throws(ImageRenderingError) -> CGColorSpace {
        switch self {
        case .source:
            guard
                let source,
                source.model == .rgb
            else {
                return CGColorSpaceCreateDeviceRGB()
            }

            return source
        case .convert(let target):
            return try target.cgColorSpace()
        }
    }
}

private extension WIColorSpace {
    func cgColorSpace() throws(ImageRenderingError) -> CGColorSpace {
        do {
            return try makeCGColorSpace()
        } catch {
            switch error {
            case .invalidICCProfile:
                throw .invalidICCProfile
            case .unavailable, .unsupportedModel:
                throw .unsupportedColorSpace
            }
        }
    }
}

private extension Rect {
    var isFiniteAndPositive: Bool {
        x.isFinite &&
        y.isFinite &&
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0
    }
}
