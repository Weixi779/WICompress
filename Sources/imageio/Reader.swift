//
//  Reader.swift
//  WIImageIO
//
//  Created by weixi on 2026/8/1.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WIImageDomain

extension WIImageIO {
    /// A read-only ImageIO source with one cached inspection result.
    public final class Reader {
        enum Input {
            case data(Data)
            case file(URL)
        }

        let source: CGImageSource
        let input: Input

        public let descriptor: Descriptor

        init(
            source: CGImageSource,
            input: Input,
            descriptor: Descriptor
        ) {
            self.source = source
            self.input = input
            self.descriptor = descriptor
        }

        /// Reads the source color space when it can be represented by WIImageIO.
        public func colorSpace() throws(WIImageIO.Error) -> ColorSpace? {
            try WIImageIO.colorSpace(source)
        }

        /// Decodes the source frame without applying its display orientation.
        public func image(
            options: DecodeOptions = .init()
        ) throws(WIImageIO.Error) -> Frame {
            Frame(
                image: try WIImageIO.image(source, options: options),
                orientation: descriptor.orientation,
                metadataProvenance: WIImageIO.metadataProvenance(source)
            )
        }

        /// Decodes a thumbnail and optionally applies its display orientation.
        public func thumbnail(
            options: ThumbnailOptions = .init()
        ) throws(WIImageIO.Error) -> Frame {
            Frame(
                image: try WIImageIO.thumbnail(source, options: options),
                orientation: options.appliesOrientationTransform
                    ? .up
                    : descriptor.orientation,
                metadataProvenance: WIImageIO.metadataProvenance(source)
            )
        }

        /// Copies the encoded source without decoding pixels when the options allow it.
        public func copy(
            as type: UTType,
            options: CopyOptions = .init()
        ) throws(WIImageIO.Error) -> Data {
            try WIImageIO.copy(
                source,
                descriptor: descriptor,
                as: type,
                options: options
            )
        }

        /// Whether source-copy can satisfy the requested type and options.
        public func canCopy(
            as type: UTType,
            options: CopyOptions = .init()
        ) -> Bool {
            WIImageIO.canCopy(
                descriptor,
                as: type,
                options: options
            )
        }

        package func originalData() throws(WIImageIO.Error) -> Data {
            switch input {
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

        package func frame(
            _ image: CGImage,
            orientation: Orientation = .up
        ) -> Frame {
            Frame(
                image: image,
                orientation: orientation,
                metadataProvenance: WIImageIO.metadataProvenance(source)
            )
        }
    }
}
