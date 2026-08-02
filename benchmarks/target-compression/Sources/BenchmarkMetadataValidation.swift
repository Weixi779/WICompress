//
//  BenchmarkMetadataValidation.swift
//  TargetCompressionBenchmark
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import WIImageIO

enum BenchmarkMetadataValidation {
    // ImageIO writes these container facts even when no source metadata is kept.
    private static let synthesizedExifKeys: Set<String> = [
        kCGImagePropertyExifColorSpace as String,
        kCGImagePropertyExifPixelXDimension as String,
        kCGImagePropertyExifPixelYDimension as String,
    ]
    private static let synthesizedTIFFKeys: Set<String> = [
        kCGImagePropertyTIFFOrientation as String
    ]
    private static let synthesizedHEIFTIFFKeys: Set<String> = [
        kCGImagePropertyTIFFTileWidth as String,
        kCGImagePropertyTIFFTileLength as String,
    ]

    static func sourceMetadataWasRetained(
        in data: Data,
        descriptor: ImageDescriptor
    ) -> Bool {
        if descriptor.hasUnmodeledMetadata {
            return true
        }

        let sourceMetadata = descriptor.metadata.subtracting([.exif, .tiff])
        if !sourceMetadata.isEmpty {
            return true
        }

        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any]
        else {
            return true
        }

        let containsExif = containsUnexpectedExif(in: properties)
        let containsTIFF = containsUnexpectedTIFF(
            in: properties,
            format: descriptor.format
        )
        return containsExif || containsTIFF
    }

    private static func containsUnexpectedExif(
        in properties: [CFString: Any]
    ) -> Bool {
        if properties.nonemptyDictionaryExists(
            for: kCGImagePropertyExifAuxDictionary
        ) {
            return true
        }

        return properties.dictionary(
            for: kCGImagePropertyExifDictionary,
            containsKeyOutside: synthesizedExifKeys
        )
    }

    private static func containsUnexpectedTIFF(
        in properties: [CFString: Any],
        format: ImageFormat
    ) -> Bool {
        var synthesizedKeys = synthesizedTIFFKeys
        if format == .heif {
            synthesizedKeys.formUnion(synthesizedHEIFTIFFKeys)
        }

        return properties.dictionary(
            for: kCGImagePropertyTIFFDictionary,
            containsKeyOutside: synthesizedKeys
        )
    }
}

private extension Dictionary where Key == CFString, Value == Any {
    func nonemptyDictionaryExists(for key: CFString) -> Bool {
        guard let dictionary = self[key] as? [AnyHashable: Any] else {
            return self[key] != nil
        }
        return !dictionary.isEmpty
    }

    func dictionary(
        for key: CFString,
        containsKeyOutside allowedKeys: Set<String>
    ) -> Bool {
        guard let value = self[key] else {
            return false
        }
        guard let dictionary = value as? [AnyHashable: Any] else {
            return true
        }

        return dictionary.keys.contains { key in
            guard let key = key as? String else {
                return true
            }
            return !allowedKeys.contains(key)
        }
    }
}
