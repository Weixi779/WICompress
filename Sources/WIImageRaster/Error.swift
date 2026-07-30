//
//  Error.swift
//  WIImageRaster
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

extension WIImageRaster {
    package enum Error: Swift.Error, Sendable, Equatable {
        case invalidSourceRect
        case invalidDestinationRect
        case sourceRectOutOfBounds
        case rowByteOverflow(width: Int)
        case bitmapByteCountOverflow(width: Int, height: Int)
        case unsupportedColorSpace
        case invalidICCProfile
        case nonOpaqueBackground
        case colorConversionFailed
        case contextCreationFailed
        case imageCreationFailed
    }
}
