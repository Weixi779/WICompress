//
//  WICompressionTargetResolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

enum WICompressionTargetResolver {
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

    static func options(for target: WICompressionTarget) throws(WICompressError) -> WICompressOptions {
        guard let resize = resizePolicy(for: target.geometry) else {
            throw WICompressError.unsupportedCompressionGeometry(target.geometry)
        }

        return WICompressOptions(
            resize: resize,
            format: target.output.format,
            metadata: target.output.metadata,
            quality: .compression(0.6),
            colorSpace: target.output.colorSpace
        )
    }

    private static func resizePolicy(for geometry: WICompressionGeometry) -> WIResizePolicy? {
        switch geometry {
        case .original:
            return WIResizePolicy.none
        case .fit(let maxLongSide):
            return .maxPixel(maxLongSide)
        case .fitInside(let box):
            return .fit(minSize: WISize(width: 1, height: 1), maxSize: box)
        case .fill, .exactCanvas:
            return nil
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
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              size.width <= Double(Int.max),
              size.height <= Double(Int.max) else {
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
    init(_ size: WISize) {
        self.init(
            width: max(Int(size.width.rounded(.toNearestOrAwayFromZero)), 1),
            height: max(Int(size.height.rounded(.toNearestOrAwayFromZero)), 1)
        )
    }

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
