//
//  WIImageOutputResolver.swift
//  WICompress
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import UniformTypeIdentifiers
import WIImageCore

struct WIResolvedOutputColorSpace: Sendable, Equatable {
    let target: ColorSpace?

    var requiresConversion: Bool {
        target != nil
    }
}

struct WIResolvedImageOutput: Sendable, Equatable {
    let destinationFormat: ImageFormat
    let destinationTypeIdentifier: String
    let jpegBackground: WIJPEGBackground?
    let colorSpace: WIResolvedOutputColorSpace
    let isWritable: Bool
}

enum WIImageOutputResolver {
    static func resolve(
        _ output: WIImageOutput,
        imageSource: WIImageSource
    ) throws(WICompressError) -> WIResolvedImageOutput {
        let destination = try resolvedDestination(
            for: output.representation,
            info: imageSource.info
        )
        let sourceColorSpace = try imageSource.processColorSpaceInfoIfNeeded(
            for: output.colorSpace
        )
        let colorSpace = try resolvedColorSpace(
            output.colorSpace,
            sourceColorSpace: sourceColorSpace
        )
        let isWritable = output.representation == .preserve
            ? imageSource.info.isSourceFormatWritable
            : WIImageFormat.canWrite(
                typeIdentifier: destination.typeIdentifier
            )

        return WIResolvedImageOutput(
            destinationFormat: destination.format,
            destinationTypeIdentifier: destination.typeIdentifier,
            jpegBackground: destination.jpegBackground,
            colorSpace: colorSpace,
            isWritable: isWritable
        )
    }

    private static func resolvedDestination(
        for representation: WIImageRepresentation,
        info: WIImageInfo
    ) throws(WICompressError) -> (
        format: ImageFormat,
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
                throw .transparentSourceRequiresBackground(
                    WIImageFormat(info.sourceFormat)
                )
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
            let coreTarget = target.imageCoreValue
            return WIResolvedOutputColorSpace(
                target: sourceColorSpace?.colorSpace == coreTarget
                    ? nil
                    : coreTarget
            )
        }
    }
}
