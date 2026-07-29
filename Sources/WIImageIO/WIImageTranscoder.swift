//
//  WIImageTranscoder.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO

package enum WIImageTranscoder {
    package static func encode(
        _ image: CGImage,
        `as` typeIdentifier: String,
        options: WIImageEncodeOptions = .init(),
        preservingMetadataFrom source: WIImageSource? = nil
    ) throws(WIImageIOError) -> Data {
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw .destinationCreationFailed(typeIdentifier)
        }

        var properties = source?.preservedMetadataProperties() ?? [:]
        if let compressionQuality = options.compressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        }

        // A CGImage has no orientation tag; copied source metadata must not rotate its pixels again.
        properties[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw .destinationFinalizationFailed(typeIdentifier)
        }

        return outputData as Data
    }
}
