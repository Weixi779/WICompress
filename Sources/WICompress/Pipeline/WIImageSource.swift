//
//  WIImageSource.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import WIImageIO

final class WIImageSource {
    let data: Data
    let info: WIImageInfo

    private let imageIOSource: WIImageIO.WIImageSource

    var cgImageSource: CGImageSource {
        imageIOSource._migrationCGImageSource
    }

    init(data: Data) throws(WICompressError) {
        let imageIOSource: WIImageIO.WIImageSource
        do {
            imageIOSource = try WIImageIO.WIImageSource(data: data)
        } catch {
            throw Self.map(error)
        }

        let descriptor = imageIOSource.descriptor
        guard descriptor.frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: descriptor.frameCount)
        }

        self.data = data
        self.imageIOSource = imageIOSource
        self.info = WIImageInfo(
            sourceFormat: WIImageFormat(descriptor.format),
            typeIdentifier: descriptor.typeIdentifier,
            pixelWidth: descriptor.pixelSize.width,
            pixelHeight: descriptor.pixelSize.height,
            orientation: descriptor.orientation,
            frameCount: descriptor.frameCount,
            isSourceFormatWritable: descriptor.isSourceFormatWritable,
            hasMetadata: descriptor.hasMetadata,
            hasGPS: descriptor.hasGPS,
            hasGainMap: descriptor.hasGainMap,
            hasAlpha: descriptor.hasAlpha
        )
    }

    func colorSpaceInfoIfNeeded(
        for policy: WIOutputColorSpace
    ) throws(WICompressError) -> WISourceColorSpaceInfo? {
        guard policy.requiresSourceColorSpaceInspection else {
            return nil
        }

        let colorSpace: WIImageIO.WIImageColorSpace?
        do {
            colorSpace = try imageIOSource.colorSpace()
        } catch {
            throw Self.map(error)
        }

        return WISourceColorSpaceInfo(
            colorSpace: colorSpace.map(WIColorSpace.init)
        )
    }

    private static func map(_ error: WIImageIOError) -> WICompressError {
        switch error {
        case .invalidImageData:
            return .invalidImageData
        case .sourcePropertiesUnavailable,
             .invalidPixelSize,
             .pixelCountOverflow,
             .imageCreationFailed:
            return .imageInfoUnavailable
        case .fileReadFailed(let url),
             .fileSizeUnavailable(let url):
            return .fileReadFailed(url)
        }
    }
}

private extension WIImageFormat {
    init(_ format: WIImageIO.WIImageFormat) {
        switch format {
        case .jpeg:
            self = .jpeg
        case .png:
            self = .png
        case .heif:
            self = .heif
        case .unknown:
            self = .unknown
        }
    }
}

private extension WIColorSpace {
    init(_ colorSpace: WIImageIO.WIImageColorSpace) {
        switch colorSpace {
        case .sRGB:
            self = .sRGB
        case .displayP3:
            self = .displayP3
        case .iccProfile(let data):
            self = .iccProfile(data)
        }
    }
}

private extension WIOutputColorSpace {
    var requiresSourceColorSpaceInspection: Bool {
        switch self {
        case .preserve:
            return false
        case .convert, .preserveIfSupported:
            return true
        }
    }
}
