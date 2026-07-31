//
//  Encoder.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

package enum Encoder {
    package static func encode(
        _ image: CGImage,
        `as` type: UTType,
        options: EncodeOptions = .init(),
        metadataFrom source: Source? = nil
    ) throws(Error) -> Data {
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw .destinationCreationFailed(type)
        }

        var properties = source?.metadataProperties(
            keeping: options.metadata
        ) ?? [:]
        if let compressionQuality = options.compressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        }

        // A CGImage has no orientation tag; copied source metadata must not rotate its pixels again.
        properties[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw .destinationFinalizationFailed(type)
        }

        return outputData as Data
    }
}
