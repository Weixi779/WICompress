//
//  WIImageRasterPlan.swift
//  WIImageRaster
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

extension WIImageRaster {
    package struct PixelSize: Sendable, Equatable {
        package var width: Int
        package var height: Int

        package init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    package struct Rect: Sendable, Equatable {
        package var x: Double
        package var y: Double
        package var width: Double
        package var height: Double

        package init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    package enum Orientation: Int, Sendable, Equatable, CaseIterable {
        case up = 1
        case upMirrored = 2
        case down = 3
        case downMirrored = 4
        case leftMirrored = 5
        case right = 6
        case rightMirrored = 7
        case left = 8
    }

    package enum AlphaMode: Sendable, Equatable {
        case preserve
        case opaque
    }

    package enum ColorSpace: Sendable, Equatable {
        case source
        case sRGB
        case displayP3
        case iccProfile(Data)
    }

    package struct Color: Sendable, Equatable {
        package var red: Double
        package var green: Double
        package var blue: Double
        package var alpha: Double
        package var colorSpace: ColorSpace

        package init(
            red: Double,
            green: Double,
            blue: Double,
            alpha: Double = 1,
            colorSpace: ColorSpace = .sRGB
        ) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
            self.colorSpace = colorSpace
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
        package var colorSpace: ColorSpace

        package init(
            canvasSize: PixelSize,
            sourceRect: Rect,
            destinationRect: Rect,
            orientation: Orientation = .up,
            alphaMode: AlphaMode = .preserve,
            canvasBackground: Color? = nil,
            imageBackground: Color? = nil,
            colorSpace: ColorSpace = .source
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
