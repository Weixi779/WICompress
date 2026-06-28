//
//  WICompressionTargetResolver.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

enum WICompressionTargetResolver {
    private static let defaultTargetQuality = WIQualityPolicy.compression(0.6)

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
            quality: defaultTargetQuality,
            colorSpace: target.output.colorSpace
        )
    }

    static func writePlan(
        for target: WICompressionTarget,
        info: WIImageInfo,
        sourceColorSpace: WISourceColorSpaceInfo?
    ) throws(WICompressError) -> WIWritePlan {
        guard let renderGeometry = renderGeometry(for: target.geometry, info: info) else {
            let options = try options(for: target)
            return try WIWritePlanResolver.resolve(
                options: options,
                info: info,
                sourceColorSpace: sourceColorSpace
            )
        }

        let destination = try WIWritePlanResolver.resolvedDestination(
            for: target.output.format,
            info: info
        )
        let canWriteDestination = target.output.format == .preserve
            ? info.isSourceFormatWritable
            : WIImageFormat.canWrite(typeIdentifier: destination.typeIdentifier)
        guard canWriteDestination else {
            throw WICompressError.unsupportedDestinationFormat(destination.format)
        }

        let quality = WIWritePlanResolver.resolvedQuality(
            for: defaultTargetQuality,
            destinationFormat: destination.format
        )
        let colorSpace = try WIWritePlanResolver.resolvedColorSpace(
            for: target.output.colorSpace,
            sourceColorSpace: sourceColorSpace
        )

        return WIWritePlan(
            path: .redrawCanvas,
            destinationFormat: destination.format,
            destinationTypeIdentifier: destination.typeIdentifier,
            maxPixelSize: nil,
            targetPixelSize: renderGeometry.canvasSize,
            renderGeometry: renderGeometry,
            metadataPolicy: target.output.metadata,
            quality: quality,
            jpegBackground: destination.jpegBackground,
            outputColorSpace: colorSpace
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

    private static func renderGeometry(
        for geometry: WICompressionGeometry,
        info: WIImageInfo
    ) -> WIRenderGeometry? {
        let sourceSize = WIPixelSize(width: info.displayWidth, height: info.displayHeight)

        switch geometry {
        case .fill(let size, let crop):
            let canvasSize = WIPixelSize(size)
            return WIRenderGeometry(
                canvasSize: canvasSize,
                destinationRect: destinationRect(
                    sourceSize: sourceSize,
                    canvasSize: canvasSize,
                    placement: .fill(crop)
                ),
                background: nil
            )
        case .exactCanvas(let size, let placement, let background):
            let canvasSize = WIPixelSize(size)
            return WIRenderGeometry(
                canvasSize: canvasSize,
                destinationRect: destinationRect(
                    sourceSize: sourceSize,
                    canvasSize: canvasSize,
                    placement: placement
                ),
                background: background
            )
        case .original, .fit, .fitInside:
            return nil
        }
    }

    private static func destinationRect(
        sourceSize: WIPixelSize,
        canvasSize: WIPixelSize,
        placement: WIImagePlacement
    ) -> WIRect {
        let sourceWidth = Double(max(sourceSize.width, 1))
        let sourceHeight = Double(max(sourceSize.height, 1))
        let canvasWidth = Double(max(canvasSize.width, 1))
        let canvasHeight = Double(max(canvasSize.height, 1))

        switch placement {
        case .stretch:
            return WIRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        case .fit(let anchor):
            let scale = min(canvasWidth / sourceWidth, canvasHeight / sourceHeight)
            let width = sourceWidth * scale
            let height = sourceHeight * scale
            return WIRect(
                x: horizontalOffset(anchor, container: canvasWidth, content: width),
                y: verticalOffset(anchor, container: canvasHeight, content: height),
                width: width,
                height: height
            )
        case .fill(let anchor):
            let scale = max(canvasWidth / sourceWidth, canvasHeight / sourceHeight)
            let width = sourceWidth * scale
            let height = sourceHeight * scale
            return WIRect(
                x: horizontalOffset(anchor, container: canvasWidth, content: width),
                y: verticalOffset(anchor, container: canvasHeight, content: height),
                width: width,
                height: height
            )
        }
    }

    private static func horizontalOffset(
        _ crop: WICropMode,
        container: Double,
        content: Double
    ) -> Double {
        switch crop {
        case .left, .topLeft, .bottomLeft:
            return 0
        case .right, .topRight, .bottomRight:
            return container - content
        case .center, .top, .bottom:
            return (container - content) / 2
        }
    }

    private static func verticalOffset(
        _ crop: WICropMode,
        container: Double,
        content: Double
    ) -> Double {
        switch crop {
        case .bottom, .bottomLeft, .bottomRight:
            return 0
        case .top, .topLeft, .topRight:
            return container - content
        case .center, .left, .right:
            return (container - content) / 2
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
