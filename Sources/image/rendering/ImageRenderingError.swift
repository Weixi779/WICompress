//
//  ImageRenderingError.swift
//  WIImageRendering
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

/// Failures produced by the image rendering boundary.
package enum ImageRenderingError: Swift.Error, Sendable, Equatable {
    /// The requested source region is empty or contains a non-finite value.
    case invalidSourceRect

    /// The destination region cannot produce valid drawable geometry.
    case invalidDestinationRect

    /// The requested source region extends beyond the orientation-adjusted image bounds.
    case sourceRectOutOfBounds

    /// A bitmap row for the requested width cannot be represented safely.
    case rowByteOverflow(width: Int)

    /// The complete bitmap allocation cannot be represented safely.
    case bitmapByteCountOverflow(width: Int, height: Int)

    /// The requested color space cannot back an RGB rendering surface.
    case unsupportedColorSpace

    /// The supplied ICC profile cannot create a valid color space.
    case invalidICCProfile

    /// A rendering background contains transparency, but backgrounds must be opaque.
    case nonOpaqueBackground

    /// A color cannot be converted into the destination rendering color space.
    case colorConversionFailed

    /// Core Graphics cannot create the requested bitmap context.
    case contextCreationFailed

    /// Core Graphics cannot finalize the bitmap context as an image.
    case imageCreationFailed
}
