//
//  WIImageRasterPlan.swift
//  WIImageRaster
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import WIImageCore

extension WIImageRaster {
    package enum AlphaMode: Sendable, Equatable {
        case preserve
        case opaque
    }

    package enum OutputColorSpace: Sendable, Equatable {
        case source
        case convert(ColorSpace)

        package static var sRGB: Self {
            .convert(.sRGB)
        }
    }

    package struct Plan: Sendable, Equatable {
        package var canvasSize: PixelSize
        package var sourceRect: Rect
        package var destinationRect: Rect
        package var orientation: Orientation
        package var alphaMode: AlphaMode
        package var canvasBackground: Color?
        package var imageBackground: Color?
        package var colorSpace: OutputColorSpace

        package init(
            canvasSize: PixelSize,
            sourceRect: Rect,
            destinationRect: Rect,
            orientation: Orientation = .up,
            alphaMode: AlphaMode = .preserve,
            canvasBackground: Color? = nil,
            imageBackground: Color? = nil,
            colorSpace: OutputColorSpace = .source
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
}
