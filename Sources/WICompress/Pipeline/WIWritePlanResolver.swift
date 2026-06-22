//
//  WIWritePlanResolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

enum WIWritePlanResolver {
    static func resolve(options: WICompressOptions, info: WIImageInfo) throws(WICompressError) -> WIWritePlan {
        guard info.sourceFormat != .unknown else {
            throw WICompressError.unsupportedSourceFormat(info.typeIdentifier)
        }

        guard let destinationTypeIdentifier = info.typeIdentifier else {
            throw WICompressError.unsupportedSourceFormat(nil)
        }

        let destinationFormat = info.sourceFormat
        let maxPixelSize = resolvedMaxPixelSize(for: options.resize, info: info)
        let quality = resolvedQuality(for: options.quality, destinationFormat: destinationFormat)

        if canReturnOriginalUpfront(options: options, info: info) {
            return WIWritePlan(
                path: .returnOriginal,
                destinationFormat: destinationFormat,
                destinationTypeIdentifier: destinationTypeIdentifier,
                maxPixelSize: maxPixelSize,
                metadataPolicy: options.metadata,
                quality: quality
            )
        }

        guard info.isSourceFormatWritable else {
            if canReturnOriginalForSizeGuard(options: options, info: info) {
                return WIWritePlan(
                    path: .returnOriginal,
                    destinationFormat: destinationFormat,
                    destinationTypeIdentifier: destinationTypeIdentifier,
                    maxPixelSize: maxPixelSize,
                    metadataPolicy: options.metadata,
                    quality: quality
                )
            }

            throw WICompressError.unsupportedDestinationFormat(destinationFormat)
        }

        let path: WIWritePath
        // Metadata preservation chooses the write path because ImageIO ties it to the write call.
        switch options.metadata {
        case .preserve:
            path = .copyFromSource
        case .strip:
            path = .redrawBitmap
        }

        return WIWritePlan(
            path: path,
            destinationFormat: destinationFormat,
            destinationTypeIdentifier: destinationTypeIdentifier,
            maxPixelSize: maxPixelSize,
            metadataPolicy: options.metadata,
            quality: quality
        )
    }

    static func canReturnOriginalForSizeGuard(options: WICompressOptions, info: WIImageInfo) -> Bool {
        // Size fallback is safe only when the original already satisfies observable policies.
        originalSatisfiesResize(options.resize, info: info)
            && originalSatisfiesFormat(options.format, info: info)
            && originalSatisfiesMetadata(options.metadata, info: info)
            && originalSatisfiesOrientation(options.metadata, info: info)
    }

    private static func canReturnOriginalUpfront(options: WICompressOptions, info: WIImageInfo) -> Bool {
        guard options.quality == .none else {
            return false
        }

        return originalSatisfiesResize(options.resize, info: info)
            && originalSatisfiesFormat(options.format, info: info)
            && originalSatisfiesMetadata(options.metadata, info: info)
            && originalSatisfiesOrientation(options.metadata, info: info)
    }

    private static func originalSatisfiesResize(_ policy: WIResizePolicy, info: WIImageInfo) -> Bool {
        switch policy {
        case .none:
            return true
        case .luban:
            let displaySize = displayDimensions(for: info)
            return WILuban.ratio(width: displaySize.width, height: displaySize.height) == 1
        }
    }

    private static func originalSatisfiesFormat(_ policy: WIFormatPolicy, info: WIImageInfo) -> Bool {
        switch policy {
        case .preserve:
            return info.typeIdentifier != nil && info.sourceFormat != .unknown
        }
    }

    private static func originalSatisfiesMetadata(_ policy: WIMetadataPolicy, info: WIImageInfo) -> Bool {
        switch policy {
        case .preserve:
            return true
        case .strip:
            return !info.hasMetadata
        }
    }

    private static func originalSatisfiesOrientation(_ policy: WIMetadataPolicy, info: WIImageInfo) -> Bool {
        // Stripped output bakes orientation into pixels, so a rotation tag is not equivalent.
        switch policy {
        case .preserve:
            return true
        case .strip:
            return info.orientation == 1
        }
    }

    private static func resolvedQuality(
        for policy: WIQualityPolicy,
        destinationFormat: WIImageFormat
    ) -> Double? {
        guard destinationFormat.supportsLossyQuality else {
            return nil
        }

        switch policy {
        case .none:
            return nil
        case .compression(let value):
            return min(max(value, 0.0), 1.0)
        }
    }

    private static func resolvedMaxPixelSize(for policy: WIResizePolicy, info: WIImageInfo) -> Int? {
        switch policy {
        case .none:
            return nil
        case .luban:
            let displaySize = displayDimensions(for: info)
            let ratio = WILuban.ratio(width: displaySize.width, height: displaySize.height)
            guard ratio > 1 else {
                return nil
            }

            let maxPixelSize = max(max(displaySize.width, displaySize.height) / ratio, 1)
            return maxPixelSize == 1 ? 1 : WILuban.ensureEven(maxPixelSize)
        }
    }

    private static func displayDimensions(for info: WIImageInfo) -> (width: Int, height: Int) {
        switch info.orientation {
        case 5, 6, 7, 8:
            return (info.pixelHeight, info.pixelWidth)
        default:
            return (info.pixelWidth, info.pixelHeight)
        }
    }
}
