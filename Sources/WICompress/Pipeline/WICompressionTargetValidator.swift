//
//  WICompressionTargetValidator.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Validates a target's legality before the resolver builds a write plan.
///
/// The image-aware overload also rejects combinations that the encoder cannot
/// honor: odd hard-geometry sizes for formats that require even pixels, and
/// non-opaque canvas backgrounds when the output is JPEG.
enum WICompressionTargetValidator {
    static func validate(_ target: WICompressionTarget) throws(WICompressError) {
        guard target.maxBytes > 0 else {
            throw WICompressError.invalidTarget
        }

        try validate(target.geometry)
    }

    static func validate(_ target: WICompressionTarget, info: WIImageInfo) throws(WICompressError) {
        try validate(target)

        if target.geometry.isHardGeometry,
           target.output.format.requiresEvenPixelSize(info: info),
           target.geometry.resolvedHardPixelSize?.hasOddSide == true {
            throw WICompressError.invalidTarget
        }

        if target.output.format.resolvesToJPEG(info: info),
           case .exactCanvas(_, _, let background) = target.geometry {
            try validateOpaqueBackground(background)
        }
    }

    private static func validate(_ geometry: WICompressionGeometry) throws(WICompressError) {
        switch geometry {
        case .original:
            return
        case .fit(let maxLongSide):
            guard maxLongSide > 0 else {
                throw WICompressError.invalidTarget
            }
        case .fitInside(let box):
            try validatePositiveFinite(box)
        case .fill(let size, _):
            try validatePositiveFinite(size)
        case .exactCanvas(let size, _, _):
            try validatePositiveFinite(size)
        }
    }

    private static func validatePositiveFinite(_ size: WISize) throws(WICompressError) {
        // Mirror WIPixelSize's rounding so a value that passes here is guaranteed
        // to convert without trapping. `Double(Int.max)` rounds up to 2^63, which
        // is not representable as Int, so a plain `<= Double(Int.max)` lets the
        // boundary through and crashes downstream.
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              Int(exactly: size.width.rounded(.toNearestOrAwayFromZero)) != nil,
              Int(exactly: size.height.rounded(.toNearestOrAwayFromZero)) != nil else {
            throw WICompressError.invalidTarget
        }
    }

    private static func validateOpaqueBackground(_ color: WIColor) throws(WICompressError) {
        guard color.alpha.isFinite, color.alpha >= 1 else {
            throw WICompressError.nonOpaqueJPEGBackground
        }
    }
}

private extension WICompressionGeometry {
    var isHardGeometry: Bool {
        switch self {
        case .fill, .exactCanvas:
            return true
        case .original, .fit, .fitInside:
            return false
        }
    }

    var resolvedHardPixelSize: WIPixelSize? {
        switch self {
        case .fill(let size, _),
             .exactCanvas(let size, _, _):
            return WIPixelSize(size)
        case .original, .fit, .fitInside:
            return nil
        }
    }
}

private extension WIPixelSize {
    var hasOddSide: Bool {
        width % 2 != 0 || height % 2 != 0
    }
}

private extension WIFormatPolicy {
    func requiresEvenPixelSize(info: WIImageInfo) -> Bool {
        switch self {
        case .heic:
            return true
        case .preserve:
            return info.sourceFormat == .heif
        case .jpeg, .pngIfAlphaOtherwiseJPEG, .png:
            return false
        }
    }

    func resolvesToJPEG(info: WIImageInfo) -> Bool {
        switch self {
        case .jpeg:
            return true
        case .pngIfAlphaOtherwiseJPEG:
            return info.hasAlpha != true
        case .preserve, .png, .heic:
            return false
        }
    }
}
