//
//  WIImageSource.swift
//  WICompressExecution
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain
import WIImageIO

struct WISourceColorSpaceInfo: Sendable, Equatable {
    let colorSpace: WIColorSpace?
}

final class WIImageSource {
    enum Backing {
        case data(Data)
        case file(URL)
    }

    let backing: Backing
    let imageIOSource: WIImageIO.Source
    let descriptor: WIImageIO.Descriptor

    var byteCount: Int {
        imageIOSource.byteCount
    }

    convenience init(data: Data) throws(WICompressError) {
        let imageIOSource: WIImageIO.Source
        do {
            imageIOSource = try WIImageIO.Source(data: data)
        } catch {
            throw Self.map(error)
        }

        try self.init(
            backing: .data(data),
            imageIOSource: imageIOSource
        )
    }

    convenience init(contentsOf url: URL) throws(WICompressError) {
        let imageIOSource: WIImageIO.Source
        do {
            imageIOSource = try WIImageIO.Source(contentsOf: url)
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
        imageIOSource: WIImageIO.Source
    ) throws(WICompressError) {
        let descriptor = imageIOSource.descriptor
        guard descriptor.frameCount == 1 else {
            throw .animatedSourceUnsupported(frameCount: descriptor.frameCount)
        }

        self.backing = backing
        self.imageIOSource = imageIOSource
        self.descriptor = descriptor
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

        let colorSpace: WIColorSpace?
        do {
            colorSpace = try imageIOSource.colorSpace()
        } catch {
            throw Self.map(error)
        }

        return WISourceColorSpaceInfo(
            colorSpace: colorSpace
        )
    }

    private static func map(_ error: WIImageIO.Error) -> WICompressError {
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
            return .destinationCreationFailed(
                .detected(from: typeIdentifier)
            )
        case .destinationFinalizationFailed(let typeIdentifier):
            return .encodeFailed(.detected(from: typeIdentifier))
        case .fileReadFailed(let url),
             .fileSizeUnavailable(let url):
            return .fileReadFailed(url)
        }
    }
}
