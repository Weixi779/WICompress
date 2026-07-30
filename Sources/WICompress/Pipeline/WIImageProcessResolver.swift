//
//  WIImageProcessResolver.swift
//  WICompress
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import UniformTypeIdentifiers

enum WIImageProcessResolver {
    static func resolve(
        _ process: WIImageProcess,
        imageSource: WIImageSource
    ) throws(WICompressError) -> WIExecutionPlan {
        let info = imageSource.info
        guard info.sourceFormat != .unknown else {
            throw .unsupportedSourceFormat(info.typeIdentifier)
        }

        try validateQuality(process.quality)

        let geometry = try WIImageProcessGeometry.resolve(
            process: process,
            sourcePixelSize: WIPixelSize(
                width: info.displayWidth,
                height: info.displayHeight
            )
        )
        let destination = try resolvedDestination(
            for: process.output.representation,
            info: info
        )
        let quality = destination.format.supportsLossyQuality
            ? process.quality
            : nil
        let sourceColorSpace = try imageSource.processColorSpaceInfoIfNeeded(
            for: process.output.colorSpace
        )
        let outputColorSpace = try resolvedColorSpace(
            process.output.colorSpace,
            sourceColorSpace: sourceColorSpace
        )

        if canReturnOriginal(
            process: process,
            geometry: geometry,
            quality: quality,
            info: info,
            outputColorSpace: outputColorSpace
        ) {
            return plan(
                operation: .returnOriginal,
                destination: destination,
                process: process,
                quality: quality,
                outputColorSpace: outputColorSpace
            )
        }

        let canWriteDestination = process.output.representation == .preserve
            ? info.isSourceFormatWritable
            : WIImageFormat.canWrite(
                typeIdentifier: destination.typeIdentifier
            )
        guard canWriteDestination else {
            throw .unsupportedDestinationFormat(destination.format)
        }

        let operation: WIExecutionPlan.Operation
        if canCopyFromSource(
            process: process,
            geometry: geometry,
            outputColorSpace: outputColorSpace
        ) {
            operation = .copyFromSource
        } else {
            let targetSize = geometry.targetPixelSize
            operation = .render(
                WIResolvedRender(
                    sourceRect: geometry.sourceRect,
                    canvasSize: targetSize,
                    destinationRect: WIRect(
                        x: 0,
                        y: 0,
                        width: Double(targetSize.width),
                        height: Double(targetSize.height)
                    ),
                    canvasBackground: nil
                )
            )
        }

        return plan(
            operation: operation,
            destination: destination,
            process: process,
            quality: quality,
            outputColorSpace: outputColorSpace
        )
    }

    private static func validateQuality(
        _ quality: Double?
    ) throws(WICompressError) {
        guard let quality else {
            return
        }
        guard quality.isFinite, (0...1).contains(quality) else {
            throw .invalidProcessQuality
        }
    }

    private static func resolvedDestination(
        for representation: WIImageRepresentation,
        info: WIImageInfo
    ) throws(WICompressError) -> (
        format: WIImageFormat,
        typeIdentifier: String,
        jpegBackground: WIJPEGBackground?
    ) {
        switch representation {
        case .preserve:
            guard let typeIdentifier = info.typeIdentifier else {
                throw .unsupportedSourceFormat(nil)
            }

            return (info.sourceFormat, typeIdentifier, nil)
        case .jpeg(let background):
            try validateJPEGBackground(background)
            if background == .disallow, info.hasAlpha == true {
                throw .transparentSourceRequiresBackground(info.sourceFormat)
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

    private static func validateJPEGBackground(
        _ background: WIJPEGBackground
    ) throws(WICompressError) {
        guard case .color(let color) = background else {
            return
        }
        guard color.alpha.isFinite, color.alpha >= 1 else {
            throw .nonOpaqueJPEGBackground
        }

        let colorSpace = try color.colorSpace.makeCGColorSpace()
        guard colorSpace.model == .rgb else {
            throw .unsupportedColorSpace
        }
    }

    private static func resolvedColorSpace(
        _ decision: WIImageColorSpace,
        sourceColorSpace: WISourceColorSpaceInfo?
    ) throws(WICompressError) -> WIResolvedOutputColorSpace {
        switch decision {
        case .preserve:
            return WIResolvedOutputColorSpace(target: nil)
        case .convert(let target):
            _ = try target.makeCGColorSpace()
            return WIResolvedOutputColorSpace(
                target: sourceColorSpace?.colorSpace == target ? nil : target
            )
        }
    }

    private static func canReturnOriginal(
        process: WIImageProcess,
        geometry: WIResolvedProcessGeometry,
        quality: Double?,
        info: WIImageInfo,
        outputColorSpace: WIResolvedOutputColorSpace
    ) -> Bool {
        guard
            process.crop == nil,
            geometry.changesPixelSize == false,
            process.output.representation == .preserve,
            quality == nil,
            outputColorSpace.requiresConversion == false
        else {
            return false
        }

        switch process.output.metadata {
        case .preserve:
            return true
        case .strip:
            return !info.hasMetadata && info.orientation == 1
        }
    }

    private static func canCopyFromSource(
        process: WIImageProcess,
        geometry: WIResolvedProcessGeometry,
        outputColorSpace: WIResolvedOutputColorSpace
    ) -> Bool {
        process.crop == nil
            && geometry.changesPixelSize == false
            && process.output.representation == .preserve
            && process.output.metadata == .preserve
            && outputColorSpace.requiresConversion == false
    }

    private static func plan(
        operation: WIExecutionPlan.Operation,
        destination: (
            format: WIImageFormat,
            typeIdentifier: String,
            jpegBackground: WIJPEGBackground?
        ),
        process: WIImageProcess,
        quality: Double?,
        outputColorSpace: WIResolvedOutputColorSpace
    ) -> WIExecutionPlan {
        WIExecutionPlan(
            operation: operation,
            destinationFormat: destination.format,
            destinationTypeIdentifier: destination.typeIdentifier,
            metadata: process.output.metadata,
            quality: quality,
            jpegBackground: destination.jpegBackground,
            outputColorSpace: outputColorSpace
        )
    }
}
