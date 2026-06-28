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
    static func resolve(
        options: WICompressOptions,
        info: WIImageInfo,
        sourceColorSpace: WISourceColorSpaceInfo? = nil
    ) throws(WICompressError) -> WIWritePlan {
        guard info.sourceFormat != .unknown else {
            throw WICompressError.unsupportedSourceFormat(info.typeIdentifier)
        }

        let destination = try resolvedDestination(for: options.format, info: info)
        let destinationFormat = destination.format
        let destinationTypeIdentifier = destination.typeIdentifier
        let resize = resolvedResize(for: options.resize, info: info)
        let quality = resolvedQuality(for: options.quality, destinationFormat: destinationFormat)
        let colorSpace = try resolvedColorSpace(
            for: options.colorSpace,
            sourceColorSpace: sourceColorSpace
        )

        if canReturnOriginalUpfront(options: options, info: info, sourceColorSpace: sourceColorSpace) {
            return writePlan(
                path: .returnOriginal,
                destinationFormat: destinationFormat,
                destinationTypeIdentifier: destinationTypeIdentifier,
                resize: resize,
                metadataPolicy: options.metadata,
                quality: quality,
                jpegBackground: destination.jpegBackground,
                outputColorSpace: colorSpace
            )
        }

        let canWriteDestination = options.format == .preserve
            ? info.isSourceFormatWritable
            : WIImageFormat.canWrite(typeIdentifier: destinationTypeIdentifier)
        guard canWriteDestination else {
            if canReturnOriginalForSizeGuard(options: options, info: info, sourceColorSpace: sourceColorSpace) {
                return writePlan(
                    path: .returnOriginal,
                    destinationFormat: destinationFormat,
                    destinationTypeIdentifier: destinationTypeIdentifier,
                    resize: resize,
                    metadataPolicy: options.metadata,
                    quality: quality,
                    jpegBackground: destination.jpegBackground,
                    outputColorSpace: colorSpace
                )
            }

            throw WICompressError.unsupportedDestinationFormat(destinationFormat)
        }

        let path: WIWritePath
        let requiresRedraw = resize.requiresRedraw || colorSpace.requiresConversion
        // Metadata preservation chooses the write path because ImageIO ties it to the write call.
        switch (options.format, options.metadata) {
        case (.preserve, .preserve) where requiresRedraw:
            path = .redrawBitmap
        case (.preserve, .preserve):
            path = .copyFromSource
        case (.preserve, .strip),
             (.jpeg, _),
             (.pngIfAlphaOtherwiseJPEG, _),
             (.png, _),
             (.heic, _):
            path = .redrawBitmap
        }

        return writePlan(
            path: path,
            destinationFormat: destinationFormat,
            destinationTypeIdentifier: destinationTypeIdentifier,
            resize: resize,
            metadataPolicy: options.metadata,
            quality: quality,
            jpegBackground: destination.jpegBackground,
            outputColorSpace: colorSpace
        )
    }

    static func canReturnOriginalForSizeGuard(
        options: WICompressOptions,
        info: WIImageInfo,
        sourceColorSpace: WISourceColorSpaceInfo? = nil
    ) -> Bool {
        // Size fallback is safe only when the original already satisfies observable policies.
        originalSatisfiesResize(options.resize, info: info)
            && originalSatisfiesFormat(options.format, info: info)
            && originalSatisfiesMetadata(options.metadata, info: info)
            && originalSatisfiesOrientation(options.metadata, info: info)
            && originalSatisfiesColorSpace(options.colorSpace, sourceColorSpace: sourceColorSpace)
    }

    private static func canReturnOriginalUpfront(
        options: WICompressOptions,
        info: WIImageInfo,
        sourceColorSpace: WISourceColorSpaceInfo? = nil
    ) -> Bool {
        guard options.quality == .none else {
            return false
        }

        return originalSatisfiesResize(options.resize, info: info)
            && originalSatisfiesFormat(options.format, info: info)
            && originalSatisfiesMetadata(options.metadata, info: info)
            && originalSatisfiesOrientation(options.metadata, info: info)
            && originalSatisfiesColorSpace(options.colorSpace, sourceColorSpace: sourceColorSpace)
    }

    private static func originalSatisfiesResize(_ policy: WIResizePolicy, info: WIImageInfo) -> Bool {
        switch policy {
        case .none:
            return true
        case .luban:
            let displaySize = info.displayDimensions
            return WILuban.ratio(width: displaySize.width, height: displaySize.height) == 1
        case .maxPixel(let maxPixel):
            let displaySize = info.displayDimensions
            let longSide = max(displaySize.width, displaySize.height)
            return max(maxPixel, 1) >= longSide
        case .fit(let minSize, let maxSize):
            return fitTargetPixelSize(for: info, minSize: minSize, maxSize: maxSize) == nil
        }
    }

    private static func originalSatisfiesFormat(_ policy: WIFormatPolicy, info: WIImageInfo) -> Bool {
        switch policy {
        case .preserve:
            return info.typeIdentifier != nil && info.sourceFormat != .unknown
        case .jpeg, .pngIfAlphaOtherwiseJPEG, .png, .heic:
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

    private static func originalSatisfiesColorSpace(
        _ policy: WIOutputColorSpace,
        sourceColorSpace: WISourceColorSpaceInfo?
    ) -> Bool {
        switch policy {
        case .preserve:
            return true
        case .convert(let target):
            return sourceColorSpace?.colorSpace == target
        case .preserveIfSupported(let supportedColorSpaces, otherwise: _):
            guard let sourceColorSpace = sourceColorSpace?.colorSpace else {
                return false
            }

            return supportedColorSpaces.contains(sourceColorSpace)
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

    private static func resolvedColorSpace(
        for policy: WIOutputColorSpace,
        sourceColorSpace: WISourceColorSpaceInfo?
    ) throws(WICompressError) -> WIResolvedOutputColorSpace {
        switch policy {
        case .preserve:
            return WIResolvedOutputColorSpace(
                target: nil
            )
        case .convert(let target):
            _ = try target.makeCGColorSpace()
            let requiresConversion = sourceColorSpace?.colorSpace != target
            return WIResolvedOutputColorSpace(
                target: requiresConversion ? target : nil
            )
        case .preserveIfSupported(let supportedColorSpaces, otherwise: let fallback):
            if let sourceColorSpace = sourceColorSpace?.colorSpace,
               supportedColorSpaces.contains(sourceColorSpace) {
                return WIResolvedOutputColorSpace(
                    target: nil
                )
            }

            _ = try fallback.makeCGColorSpace()
            return WIResolvedOutputColorSpace(
                target: fallback
            )
        }
    }

    private static func resolvedResize(for policy: WIResizePolicy, info: WIImageInfo) -> WIResolvedResize {
        switch policy {
        case .none:
            return WIResolvedResize()
        case .luban:
            let displaySize = info.displayDimensions
            let ratio = WILuban.ratio(width: displaySize.width, height: displaySize.height)
            guard ratio > 1 else {
                return WIResolvedResize()
            }

            let maxPixelSize = max(max(displaySize.width, displaySize.height) / ratio, 1)
            return WIResolvedResize(maxPixelSize: maxPixelSize == 1 ? 1 : WILuban.ensureEven(maxPixelSize))
        case .maxPixel(let maxPixel):
            let displaySize = info.displayDimensions
            let longSide = max(displaySize.width, displaySize.height)
            let cappedMaxPixel = max(maxPixel, 1)
            guard cappedMaxPixel < longSide else {
                return WIResolvedResize()
            }

            return WIResolvedResize(maxPixelSize: cappedMaxPixel)
        case .fit(let minSize, let maxSize):
            guard let targetPixelSize = fitTargetPixelSize(for: info, minSize: minSize, maxSize: maxSize) else {
                return WIResolvedResize()
            }

            let displaySize = info.displayDimensions
            let targetLongSide = max(targetPixelSize.width, targetPixelSize.height)
            let sourceLongSide = max(displaySize.width, displaySize.height)

            return WIResolvedResize(
                maxPixelSize: targetLongSide < sourceLongSide ? targetLongSide : nil,
                targetPixelSize: targetPixelSize,
                requiresRedraw: targetLongSide > sourceLongSide
            )
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
            try validateJPEGBackground(background)
            if background == .disallow, info.hasAlpha == true {
                throw WICompressError.transparentSourceRequiresBackground(info.sourceFormat)
            }

            return (.jpeg, UTType.jpeg.identifier, background)
        case .pngIfAlphaOtherwiseJPEG:
            if info.hasAlpha == true {
                return (.png, UTType.png.identifier, nil)
            }

            return (.jpeg, UTType.jpeg.identifier, .disallow)
        case .png:
            return (.png, UTType.png.identifier, nil)
        case .heic:
            return (.heif, UTType.heic.identifier, nil)
        }
    }

    private static func validateJPEGBackground(_ background: WIJPEGBackground) throws(WICompressError) {
        guard case .color(let color) = background else {
            return
        }

        guard color.alpha.isFinite, color.alpha >= 1 else {
            throw WICompressError.nonOpaqueJPEGBackground
        }

        let colorSpace = try color.colorSpace.makeCGColorSpace()
        guard colorSpace.model == .rgb else {
            throw WICompressError.unsupportedColorSpace
        }
    }

    private static func fitTargetPixelSize(
        for info: WIImageInfo,
        minSize: WISize,
        maxSize: WISize
    ) -> WIPixelSize? {
        let displaySize = info.displayDimensions
        let width = Double(max(displaySize.width, 1))
        let height = Double(max(displaySize.height, 1))
        let minWidth = positiveDimension(minSize.width)
        let minHeight = positiveDimension(minSize.height)
        let maxWidth = max(positiveDimension(maxSize.width), minWidth)
        let maxHeight = max(positiveDimension(maxSize.height), minHeight)

        let scale: Double
        if width < minWidth, height < minHeight {
            scale = min(minWidth / width, minHeight / height)
        } else if width > maxWidth || height > maxHeight {
            scale = min(maxWidth / width, maxHeight / height)
        } else {
            return nil
        }

        let targetWidth = max(Int((width * scale).rounded(.toNearestOrAwayFromZero)), 1)
        let targetHeight = max(Int((height * scale).rounded(.toNearestOrAwayFromZero)), 1)
        return WIPixelSize(width: targetWidth, height: targetHeight)
    }

    private static func positiveDimension(_ value: Double) -> Double {
        value.isFinite ? max(value, 1.0) : 1.0
    }

    private static func writePlan(
        path: WIWritePath,
        destinationFormat: WIImageFormat,
        destinationTypeIdentifier: String,
        resize: WIResolvedResize,
        metadataPolicy: WIMetadataPolicy,
        quality: Double?,
        jpegBackground: WIJPEGBackground?,
        outputColorSpace: WIResolvedOutputColorSpace
    ) -> WIWritePlan {
        WIWritePlan(
            path: path,
            destinationFormat: destinationFormat,
            destinationTypeIdentifier: destinationTypeIdentifier,
            maxPixelSize: resize.maxPixelSize,
            targetPixelSize: resize.targetPixelSize,
            metadataPolicy: metadataPolicy,
            quality: quality,
            jpegBackground: jpegBackground,
            outputColorSpace: outputColorSpace
        )
    }
}

private struct WIResolvedResize: Sendable, Equatable {
    var maxPixelSize: Int?
    var targetPixelSize: WIPixelSize?
    var requiresRedraw: Bool

    init(
        maxPixelSize: Int? = nil,
        targetPixelSize: WIPixelSize? = nil,
        requiresRedraw: Bool = false
    ) {
        self.maxPixelSize = maxPixelSize
        self.targetPixelSize = targetPixelSize
        self.requiresRedraw = requiresRedraw
    }
}
