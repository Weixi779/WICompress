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
        let source: CGImageSource

        public let descriptor: Descriptor

        init(
            source: CGImageSource,
            descriptor: Descriptor
        ) {
            self.source = source
            self.descriptor = descriptor
        }

        /// Reads the source color space when it can be represented by WIImageIO.
        public func colorSpace() throws(WIImageIO.Error) -> WIColorSpace? {
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

        /// Transcodes the encoded source without decoding pixels when the options allow it.
        public func transcode(
            as type: UTType,
            options: TranscodeOptions = .init()
        ) throws(WIImageIO.Error) -> Data {
            try WIImageIO.transcode(
                source,
                descriptor: descriptor,
                as: type,
                options: options
            )
        }

        package func canTranscode(
            as type: UTType,
            options: TranscodeOptions = .init()
        ) -> Bool {
            WIImageIO.canTranscode(
                descriptor,
                as: type,
                options: options
            )
        }

        package func frame(
            _ image: CGImage,
            orientation: WIImageOrientation = .up
        ) -> Frame {
            Frame(
                image: image,
                orientation: orientation,
                metadataProvenance: WIImageIO.metadataProvenance(source)
            )
        }
    }
}
