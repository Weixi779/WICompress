//
//  Error.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

package enum Error: Swift.Error, Sendable, Equatable {
    case invalidImageData
    case sourcePropertiesUnavailable
    case invalidPixelSize(width: Int, height: Int)
    case pixelCountOverflow(width: Int, height: Int)
    case fileReadFailed(URL)
    case fileSizeUnavailable(URL)
    case imageCreationFailed
    case thumbnailCreationFailed
    case animatedSourceUnsupported(frameCount: Int)
    case destinationCreationFailed(String)
    case destinationFinalizationFailed(String)
}
