//
//  WIImageFormat.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageCore
import WIImageIO

/// Image container families supported by WICompress.
public enum WIImageFormat: Sendable, Equatable {
    /// JPEG image data.
    case jpeg
    /// PNG image data.
    case png
    /// HEIC or HEIF image data.
    case heif
    /// Unknown or unsupported image data.
    case unknown

    /// Whether the format is HEIC or HEIF.
    public var isHEIF: Bool {
        return self == .heif
    }

    init(typeIdentifier: String?) {
        self.init(ImageFormat(typeIdentifier: typeIdentifier))
    }

    static func canWrite(typeIdentifier: String) -> Bool {
        Capabilities.canEncode(typeIdentifier: typeIdentifier)
    }

    /// Detects the image format from container bytes.
    public init(data: Data) {
        self.init(ImageFormat(data: data))
    }

    init(_ format: ImageFormat) {
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
