//
//  WIImageOutputResolver.swift
//  WICompressExecution
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import WIImageDomain
import WIImageIO

struct WIResolvedOutputColorSpace: Sendable, Equatable {
    let target: WIColorSpace?

    var requiresConversion: Bool {
        target != nil
    }
}

struct WIResolvedImageOutput: Sendable, Equatable {
    let destinationFormat: WIImageFormat
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
            descriptor: imageSource.descriptor
        )
        let colorSpace = try resolvedColorSpace(
            output.colorSpace,
            imageSource: imageSource
        )
        let isWritable = output.representation == .preserve
            ? imageSource.descriptor.isSourceFormatWritable
            : Capabilities.canEncode(
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
        descriptor: WIImageIO.Descriptor
    ) throws(WICompressError) -> (
        format: WIImageFormat,
        typeIdentifier: String,
        jpegBackground: WIJPEGBackground?
    ) {
        switch representation {
        case .preserve:
            guard let typeIdentifier = descriptor.typeIdentifier else {
                throw .unsupportedSourceFormat(nil)
            }

            return (descriptor.format, typeIdentifier, nil)
        case .jpeg(let background):
            try validateJPEGBackground(background)
            if background == .disallow, descriptor.hasAlpha == true {
                throw .transparentSourceRequiresBackground(descriptor.format)
            }

            return (.jpeg, UTType.jpeg.identifier, background)
        case .pngIfAlphaOtherwiseJPEG:
            if descriptor.hasAlpha == true {
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

        let colorSpace = try makeCGColorSpace(color.colorSpace)
        guard colorSpace.model == .rgb else {
            throw .unsupportedColorSpace
        }
    }

    private static func resolvedColorSpace(
        _ decision: WIImageColorSpace,
        imageSource: WIImageSource
    ) throws(WICompressError) -> WIResolvedOutputColorSpace {
        switch decision {
        case .preserve:
            return WIResolvedOutputColorSpace(target: nil)
        case .convert(let target):
            _ = try makeCGColorSpace(target)
            let sourceColorSpace = try imageSource.sourceColorSpace()
            return WIResolvedOutputColorSpace(
                target: sourceColorSpace == target
                    ? nil
                    : target
            )
        }
    }

    private static func makeCGColorSpace(
        _ colorSpace: WIColorSpace
    ) throws(WICompressError) -> CGColorSpace {
        do {
            return try colorSpace.makeCGColorSpace()
        } catch {
            switch error {
            case .invalidICCProfile:
                throw .invalidICCProfile
            case .unavailable, .unsupportedModel:
                throw .unsupportedColorSpace
            }
        }
    }
}
