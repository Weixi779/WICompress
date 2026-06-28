//
//  WICompressionGeometry.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Crop anchor used when filling a target rectangle.
public enum WICropMode: Sendable, Equatable {
    /// Crop around the center.
    case center
    /// Preserve the top edge.
    case top
    /// Preserve the bottom edge.
    case bottom
    /// Preserve the left edge.
    case left
    /// Preserve the right edge.
    case right
    /// Preserve the top-left corner.
    case topLeft
    /// Preserve the top-right corner.
    case topRight
    /// Preserve the bottom-left corner.
    case bottomLeft
    /// Preserve the bottom-right corner.
    case bottomRight
}

/// Placement mode used when drawing an image into an exact canvas.
public enum WIImagePlacement: Sendable, Equatable {
    /// Preserve the full image and allow background around it.
    case fit(WICropMode = .center)
    /// Fill the canvas and allow image content to be cropped.
    case fill(WICropMode = .center)
    /// Stretch pixels to the canvas size.
    case stretch
}

/// Output geometry intent for target-based compression.
public enum WICompressionGeometry: Sendable, Equatable {
    /// Start from the source display dimensions.
    case original
    /// Preserve aspect ratio and cap the longest display side.
    case fit(maxLongSide: Int)
    /// Preserve aspect ratio and fit inside the supplied box.
    case fitInside(box: WISize)
    /// Produce the exact visual size by scaling and cropping.
    case fill(size: WISize, crop: WICropMode = .center)
    /// Produce the exact canvas size by placing the image over a background.
    case exactCanvas(size: WISize, placement: WIImagePlacement = .fit(.center), background: WIColor)
}
