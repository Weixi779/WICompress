//
//  Metadata.swift
//  WIImageIO
//
//  Created by weixi on 2026/8/1.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import WIImageDomain

extension WIImageIO {
    struct MetadataProvenance {
        let sourceProperties: [CFString: Any]

        func properties(
            keeping options: WIImageMetadataOptions
        ) -> [CFString: Any] {
            WIImageIO.metadataProperties(
                in: sourceProperties,
                keeping: options
            )
        }
    }

    static func metadataProvenance(
        _ source: CGImageSource
    ) -> MetadataProvenance? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any]
        else {
            return nil
        }
        return MetadataProvenance(sourceProperties: properties)
    }

    static func metadataOptions(
        in properties: [CFString: Any]
    ) -> WIImageMetadataOptions {
        var options: WIImageMetadataOptions = []
        for option in WIImageMetadataOptions.all.singleOptions {
            if !metadataProperties(
                in: properties,
                keeping: option
            ).isEmpty {
                options.insert(option)
            }
        }
        return options
    }

    static func metadataProperties(
        in properties: [CFString: Any],
        keeping options: WIImageMetadataOptions
    ) -> [CFString: Any] {
        var metadata: [CFString: Any] = metadataKeys(
            for: options
        ).reduce(into: [:]) { result, key in
            if properties.dictionaryExists(for: key),
                let value = properties[key]
            {
                result[key] = value
            }
        }

        if options.contains(.makerNotes) {
            if !options.contains(.exif),
                let makerNote = exifMakerNote(in: properties)
            {
                metadata[kCGImagePropertyExifDictionary] = [
                    kCGImagePropertyExifMakerNote: makerNote
                ]
            }
        } else {
            remove(
                kCGImagePropertyExifMakerNote,
                from: kCGImagePropertyExifDictionary,
                in: &metadata
            )
        }

        removeDisplayOrientation(from: &metadata)
        return metadata
    }

    static func hasUnmodeledMetadata(
        in source: CGImageSource,
        properties: [CFString: Any]
    ) -> Bool {
        if properties.dictionaryExists(for: kCGImageProperty8BIMDictionary)
            || hasPNGTextMetadata(in: properties)
        {
            return true
        }

        guard
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
            let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
        else {
            return false
        }

        return tags.contains { tag in
            guard let namespace = CGImageMetadataTagCopyNamespace(tag) as String? else {
                return false
            }
            return !recognizedMetadataNamespaces.contains(namespace)
        }
    }

    static func hasGainMap(in source: CGImageSource) -> Bool {
        if #available(iOS 14.1, macOS 11.0, *) {
            return CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source,
                0,
                kCGImageAuxiliaryDataTypeHDRGainMap
            ) != nil
        }
        return false
    }

    private static func metadataKeys(
        for options: WIImageMetadataOptions
    ) -> [CFString] {
        var keys: [CFString] = []
        if options.contains(.exif) {
            keys.append(kCGImagePropertyExifDictionary)
            keys.append(kCGImagePropertyExifAuxDictionary)
        }
        if options.contains(.gps) {
            keys.append(kCGImagePropertyGPSDictionary)
        }
        if options.contains(.iptc) {
            keys.append(kCGImagePropertyIPTCDictionary)
        }
        if options.contains(.tiff) {
            keys.append(kCGImagePropertyTIFFDictionary)
        }
        if options.contains(.makerNotes) {
            keys.append(kCGImagePropertyMakerAppleDictionary)
            keys.append(kCGImagePropertyMakerCanonDictionary)
            keys.append(kCGImagePropertyMakerNikonDictionary)
            keys.append(kCGImagePropertyMakerMinoltaDictionary)
            keys.append(kCGImagePropertyMakerFujiDictionary)
            keys.append(kCGImagePropertyMakerOlympusDictionary)
            keys.append(kCGImagePropertyMakerPentaxDictionary)
        }
        return keys
    }

    private static func exifMakerNote(
        in properties: [CFString: Any]
    ) -> Any? {
        guard
            let exif = properties[kCGImagePropertyExifDictionary]
                as? [AnyHashable: Any]
        else {
            return nil
        }
        return exif[kCGImagePropertyExifMakerNote]
    }

    private static func hasPNGTextMetadata(
        in properties: [CFString: Any]
    ) -> Bool {
        guard
            let png = properties[kCGImagePropertyPNGDictionary]
                as? [AnyHashable: Any]
        else {
            return false
        }

        let textKeys: [CFString] = [
            kCGImagePropertyPNGAuthor,
            kCGImagePropertyPNGComment,
            kCGImagePropertyPNGCopyright,
            kCGImagePropertyPNGCreationTime,
            kCGImagePropertyPNGDescription,
            kCGImagePropertyPNGDisclaimer,
            kCGImagePropertyPNGModificationTime,
            kCGImagePropertyPNGSoftware,
            kCGImagePropertyPNGSource,
            kCGImagePropertyPNGTitle,
            kCGImagePropertyPNGWarning,
        ]
        return textKeys.contains { png[$0] != nil }
    }

    private static func removeDisplayOrientation(
        from metadata: inout [CFString: Any]
    ) {
        remove(
            kCGImagePropertyTIFFOrientation,
            from: kCGImagePropertyTIFFDictionary,
            in: &metadata
        )
        remove(
            kCGImagePropertyIPTCImageOrientation,
            from: kCGImagePropertyIPTCDictionary,
            in: &metadata
        )
    }

    private static func remove(
        _ property: CFString,
        from dictionaryKey: CFString,
        in metadata: inout [CFString: Any]
    ) {
        guard var dictionary = metadata[dictionaryKey] as? [AnyHashable: Any] else {
            return
        }

        dictionary.removeValue(forKey: property)
        if dictionary.isEmpty {
            metadata.removeValue(forKey: dictionaryKey)
        } else {
            metadata[dictionaryKey] = dictionary
        }
    }

    // ImageIO synthesizes technical tags in its private namespace from ordinary
    // image properties, so their presence does not imply independent metadata.
    private static let recognizedMetadataNamespaces: Set<String> = [
        kCGImageMetadataNamespaceExif as String,
        kCGImageMetadataNamespaceExifAux as String,
        kCGImageMetadataNamespaceExifEX as String,
        kCGImageMetadataNamespaceIPTCCore as String,
        kCGImageMetadataNamespaceIPTCExtension as String,
        kCGImageMetadataNamespaceTIFF as String,
        "http://ns.apple.com/ImageIO/1.0/",
    ]
}

extension WIImageMetadataOptions {
    fileprivate var singleOptions: [Self] {
        [.exif, .gps, .iptc, .tiff, .makerNotes].filter(contains)
    }
}

extension Dictionary where Key == CFString, Value == Any {
    fileprivate func dictionaryExists(for key: CFString) -> Bool {
        guard let dictionary = self[key] as? [AnyHashable: Any] else {
            return false
        }
        return !dictionary.isEmpty
    }
}
