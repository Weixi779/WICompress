//
//  WIImageSource.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageIO

final class WIImageSource {
    enum Backing {
        case data(Data)
        case file(URL)
    }

    let backing: Backing
    let info: WIImageInfo

    let imageIOSource: WIImageIO.WIImageSource

    var byteCount: Int {
        imageIOSource.byteCount
    }

    convenience init(data: Data) throws(WICompressError) {
        let imageIOSource: WIImageIO.WIImageSource
        do {
            imageIOSource = try WIImageIO.WIImageSource(data: data)
        } catch {
            throw Self.map(error)
        }

        try self.init(
            backing: .data(data),
            imageIOSource: imageIOSource
        )
    }

    convenience init(contentsOf url: URL) throws(WICompressError) {
        let imageIOSource: WIImageIO.WIImageSource
        do {
            imageIOSource = try WIImageIO.WIImageSource(contentsOf: url)
        } catch {
            throw Self.map(error)
        }

        try self.init(
            backing: .file(url),
            imageIOSource: imageIOSource
        )
    }

    private init(
        backing: Backing,
        imageIOSource: WIImageIO.WIImageSource
    ) throws(WICompressError) {
        let descriptor = imageIOSource.descriptor
        guard descriptor.frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: descriptor.frameCount)
        }

        self.backing = backing
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

    func originalData() throws(WICompressError) -> Data {
        switch backing {
        case .data(let data):
            return data
        case .file(let url):
            do {
                return try Data(contentsOf: url)
            } catch {
                throw .fileReadFailed(url)
            }
        }
    }

    func processColorSpaceInfoIfNeeded(
        for decision: WIImageColorSpace
    ) throws(WICompressError) -> WISourceColorSpaceInfo? {
        guard case .convert = decision else {
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
        case .thumbnailCreationFailed:
            return .thumbnailCreationFailed
        case .animatedSourceUnsupported(let frameCount):
            return .animatedSourceUnsupported(frameCount: frameCount)
        case .destinationCreationFailed(let typeIdentifier):
            return .destinationCreationFailed(WIImageFormat(typeIdentifier: typeIdentifier))
        case .destinationFinalizationFailed(let typeIdentifier):
            return .encodeFailed(WIImageFormat(typeIdentifier: typeIdentifier))
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
