//
//  WIWritePlanResolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import UniformTypeIdentifiers

enum WIWritePlanResolver {
    static func resolve(options: WICompressOptions, info: WIImageInfo) throws(WICompressError) -> WIWritePlan {
        guard info.sourceFormat != .unknown else {
            throw WICompressError.unsupportedSourceFormat(info.typeIdentifier)
        }

        let destination = try resolvedDestination(for: options.format, info: info)
        let destinationFormat = destination.format
        let destinationTypeIdentifier = destination.typeIdentifier
        let maxPixelSize = resolvedMaxPixelSize(for: options.resize, info: info)
        let quality = resolvedQuality(for: options.quality, destinationFormat: destinationFormat)

        if canReturnOriginalUpfront(options: options, info: info) {
            return WIWritePlan(
                path: .returnOriginal,
                destinationFormat: destinationFormat,
                destinationTypeIdentifier: destinationTypeIdentifier,
                maxPixelSize: maxPixelSize,
                metadataPolicy: options.metadata,
                quality: quality,
                jpegBackground: destination.jpegBackground
            )
        }

        let canWriteDestination = options.format == .preserve
            ? info.isSourceFormatWritable
            : WIImageFormat.canWrite(typeIdentifier: destinationTypeIdentifier)
        guard canWriteDestination else {
            if canReturnOriginalForSizeGuard(options: options, info: info) {
                return WIWritePlan(
                    path: .returnOriginal,
                    destinationFormat: destinationFormat,
                    destinationTypeIdentifier: destinationTypeIdentifier,
                    maxPixelSize: maxPixelSize,
                    metadataPolicy: options.metadata,
                    quality: quality,
                    jpegBackground: destination.jpegBackground
                )
            }

            throw WICompressError.unsupportedDestinationFormat(destinationFormat)
        }

        let path: WIWritePath
        // Metadata preservation chooses the write path because ImageIO ties it to the write call.
        switch (options.format, options.metadata) {
        case (.preserve, .preserve):
            path = .copyFromSource
        case (.preserve, .strip), (.jpeg, _), (.png, _), (.heic, _):
            path = .redrawBitmap
        }

        return WIWritePlan(
            path: path,
            destinationFormat: destinationFormat,
            destinationTypeIdentifier: destinationTypeIdentifier,
            maxPixelSize: maxPixelSize,
            metadataPolicy: options.metadata,
            quality: quality,
            jpegBackground: destination.jpegBackground
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
        case .maxPixel(let maxPixel):
            let displaySize = displayDimensions(for: info)
            let longSide = max(displaySize.width, displaySize.height)
            return max(maxPixel, 1) >= longSide
        }
    }

    private static func originalSatisfiesFormat(_ policy: WIFormatPolicy, info: WIImageInfo) -> Bool {
        switch policy {
        case .preserve:
            return info.typeIdentifier != nil && info.sourceFormat != .unknown
        case .jpeg, .png, .heic:
            return false
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
        case .maxPixel(let maxPixel):
            let displaySize = displayDimensions(for: info)
            let longSide = max(displaySize.width, displaySize.height)
            let cappedMaxPixel = max(maxPixel, 1)
            guard cappedMaxPixel < longSide else {
                return nil
            }

            return cappedMaxPixel
        }
    }

    private static func resolvedDestination(
        for policy: WIFormatPolicy,
        info: WIImageInfo
    ) throws(WICompressError) -> (format: WIImageFormat, typeIdentifier: String, jpegBackground: WIJPEGBackground?) {
        switch policy {
        case .preserve:
            guard let typeIdentifier = info.typeIdentifier else {
                throw WICompressError.unsupportedSourceFormat(nil)
            }

            return (info.sourceFormat, typeIdentifier, nil)
        case .jpeg(let background):
            if background == .disallow, info.hasAlpha == true {
                throw WICompressError.transparentSourceRequiresBackground(info.sourceFormat)
            }

            return (.jpeg, UTType.jpeg.identifier, background)
        case .png:
            return (.png, UTType.png.identifier, nil)
        case .heic:
            return (.heif, UTType.heic.identifier, nil)
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
