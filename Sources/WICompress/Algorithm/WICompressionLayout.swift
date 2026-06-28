//
//  WICompressionLayout.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Pure placement math that maps a source size onto a fixed canvas.
///
/// Offsets are expressed in the bottom-left-origin (y-up) space used by the
/// canvas render context: a `.top` anchor keeps the top of the image by pushing
/// content up, and `.fill` scales past the canvas so the excess is clipped.
enum WICompressionLayout {
    static func destinationRect(
        sourceSize: WIPixelSize,
        canvasSize: WIPixelSize,
        placement: WIImagePlacement
    ) -> WIRect {
        let sourceWidth = Double(max(sourceSize.width, 1))
        let sourceHeight = Double(max(sourceSize.height, 1))
        let canvasWidth = Double(max(canvasSize.width, 1))
        let canvasHeight = Double(max(canvasSize.height, 1))

        switch placement {
        case .stretch:
            return WIRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        case .fit(let anchor):
            let scale = min(canvasWidth / sourceWidth, canvasHeight / sourceHeight)
            return anchoredRect(
                anchor: anchor,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
                contentWidth: sourceWidth * scale,
                contentHeight: sourceHeight * scale
            )
        case .fill(let anchor):
            let scale = max(canvasWidth / sourceWidth, canvasHeight / sourceHeight)
            return anchoredRect(
                anchor: anchor,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight,
                contentWidth: sourceWidth * scale,
                contentHeight: sourceHeight * scale
            )
        }
    }

    private static func anchoredRect(
        anchor: WICropMode,
        canvasWidth: Double,
        canvasHeight: Double,
        contentWidth: Double,
        contentHeight: Double
    ) -> WIRect {
        WIRect(
            x: horizontalOffset(anchor, container: canvasWidth, content: contentWidth),
            y: verticalOffset(anchor, container: canvasHeight, content: contentHeight),
            width: contentWidth,
            height: contentHeight
        )
    }

    private static func horizontalOffset(
        _ crop: WICropMode,
        container: Double,
        content: Double
    ) -> Double {
        switch crop {
        case .left, .topLeft, .bottomLeft:
            return 0
        case .right, .topRight, .bottomRight:
            return container - content
        case .center, .top, .bottom:
            return (container - content) / 2
        }
    }

    private static func verticalOffset(
        _ crop: WICropMode,
        container: Double,
        content: Double
    ) -> Double {
        switch crop {
        case .bottom, .bottomLeft, .bottomRight:
            return 0
        case .top, .topLeft, .topRight:
            return container - content
        case .center, .left, .right:
            return (container - content) / 2
        }
    }
}
