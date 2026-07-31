//
//  ImagePipeline+Output.swift
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

struct DestinationColorSpace: Sendable, Equatable {
    let target: WIColorSpace?

    var requiresConversion: Bool {
        target != nil
    }
}

struct ImageDestination: Sendable, Equatable {
    let destinationType: UTType
    let jpegBackground: WIJPEGBackground?
    let colorSpace: DestinationColorSpace
    let isWritable: Bool

    var destinationFormat: WIImageFormat {
        .detected(from: destinationType)
    }
}

extension ImagePipeline {
    func imageDestination(
        _ output: WIImageOutput
    ) throws(WICompressError) -> ImageDestination {
        let destination = try destination(
            for: output.representation
        )
        let colorSpace = try outputColorSpace(output.colorSpace)
        let isWritable = Capabilities.canEncode(destination.type)

        return ImageDestination(
            destinationType: destination.type,
            jpegBackground: destination.jpegBackground,
            colorSpace: colorSpace,
            isWritable: isWritable
        )
    }

    private func destination(
        for representation: WIImageRepresentation
    ) throws(WICompressError) -> (
        type: UTType,
        jpegBackground: WIJPEGBackground?
    ) {
        switch representation {
        case .preserve:
            guard let type = descriptor.type else {
                throw .unsupportedSourceFormat(nil)
            }

            return (type, nil)
        case .jpeg(let background):
            try validateJPEGBackground(background)
            if background == .disallow, descriptor.hasAlpha == true {
                throw .transparentSourceRequiresBackground(descriptor.format)
            }

            return (.jpeg, background)
        case .pngIfAlphaOtherwiseJPEG:
            if descriptor.hasAlpha == true {
                return (.png, nil)
            }

            return (.jpeg, .disallow)
        case .png:
            return (.png, nil)
        case .heic:
            return (.heic, nil)
        }
    }

    private func validateJPEGBackground(
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

    private func outputColorSpace(
        _ decision: WIImageColorSpace
    ) throws(WICompressError) -> DestinationColorSpace {
        switch decision {
        case .preserve:
            return DestinationColorSpace(target: nil)
        case .convert(let target):
            _ = try makeCGColorSpace(target)
            let sourceColorSpace = try sourceColorSpace()
            return DestinationColorSpace(
                target: sourceColorSpace == target
                    ? nil
                    : target
            )
        }
    }

    private func makeCGColorSpace(
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
