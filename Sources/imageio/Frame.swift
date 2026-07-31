//
//  Frame.swift
//  WIImageIO
//
//  Created by weixi on 2026/8/1.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import WIImageDomain

extension WIImageIO {
    /// Decoded pixels with explicit orientation and optional source metadata provenance.
    public struct Frame {
        public let image: CGImage
        public let orientation: Orientation

        private let metadataProvenance: MetadataProvenance?

        public var pixelSize: PixelSize {
            PixelSize(width: image.width, height: image.height)
        }

        /// Wraps caller-owned pixels without source metadata provenance.
        public init(
            image: CGImage,
            orientation: Orientation = .up
        ) {
            self.image = image
            self.orientation = orientation
            self.metadataProvenance = nil
        }

        init(
            image: CGImage,
            orientation: Orientation,
            metadataProvenance: MetadataProvenance?
        ) {
            self.image = image
            self.orientation = orientation
            self.metadataProvenance = metadataProvenance
        }

        /// Encodes the frame while retaining selected source metadata when available.
        public func encode(
            as type: UTType,
            options: EncodeOptions = .init()
        ) throws(WIImageIO.Error) -> Data {
            let metadata = metadataProvenance?.properties(
                keeping: options.metadata
            ) ?? [:]

            return try WIImageIO.encode(
                image,
                as: type,
                options: options,
                metadata: metadata,
                orientation: orientation
            )
        }
    }

    struct MetadataProvenance {
        let sourceProperties: [CFString: Any]

        func properties(
            keeping options: MetadataOptions
        ) -> [CFString: Any] {
            WIImageIO.metadataProperties(
                in: sourceProperties,
                keeping: options
            )
        }
    }
}
