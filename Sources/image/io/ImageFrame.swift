//
//  ImageFrame.swift
//  WIImageIO
//
//  Created by weixi on 2026/8/1.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import WIImageDomain

/// Decoded pixels with explicit orientation and optional source metadata provenance.
public struct ImageFrame {
    public let image: CGImage
    public let orientation: WIImageOrientation

    let metadataProvenance: MetadataProvenance?

    public var pixelSize: WIPixelSize {
        WIPixelSize(width: image.width, height: image.height)
    }

    /// Wraps caller-owned pixels without source metadata provenance.
    public init(
        image: CGImage,
        orientation: WIImageOrientation = .up
    ) {
        self.image = image
        self.orientation = orientation
        self.metadataProvenance = nil
    }

    init(
        image: CGImage,
        orientation: WIImageOrientation,
        metadataProvenance: MetadataProvenance?
    ) {
        self.image = image
        self.orientation = orientation
        self.metadataProvenance = metadataProvenance
    }
}

extension ImageReader {
    package func frame(
        _ image: CGImage,
        orientation: WIImageOrientation = .up
    ) -> ImageFrame {
        ImageFrame(
            image: image,
            orientation: orientation,
            metadataProvenance: Self.metadataProvenance(source)
        )
    }
}
