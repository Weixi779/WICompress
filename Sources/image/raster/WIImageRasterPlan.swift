//
//  WIImageRasterPlan.swift
//  WIImageRaster
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import WIImageDomain

extension WIImageRaster {
    package enum AlphaMode: Sendable, Equatable {
        case preserve
        case opaque
    }

    package enum OutputColorSpace: Sendable, Equatable {
        case source
        case convert(WIColorSpace)

        package static var sRGB: Self {
            .convert(.sRGB)
        }
    }

    package struct Plan: Sendable, Equatable {
        package var canvasSize: WIPixelSize
        package var sourceRect: Rect
        package var destinationRect: Rect
        package var orientation: WIImageOrientation
        package var alphaMode: AlphaMode
        package var canvasBackground: WIColor?
        package var imageBackground: WIColor?
        package var colorSpace: OutputColorSpace

        package init(
            canvasSize: WIPixelSize,
            sourceRect: Rect,
            destinationRect: Rect,
            orientation: WIImageOrientation = .up,
            alphaMode: AlphaMode = .preserve,
            canvasBackground: WIColor? = nil,
            imageBackground: WIColor? = nil,
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
