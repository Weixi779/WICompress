//
//  WIImageFormat.swift
//  WIImageIO
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import UniformTypeIdentifiers

/// Image container families produced by WICompress.
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
        self == .heif
    }

    package static func detected(from typeIdentifier: String?) -> Self {
        guard
            let typeIdentifier,
            let type = UTType(typeIdentifier)
        else {
            return .unknown
        }

        if type.conforms(to: .jpeg) {
            return .jpeg
        }
        if type.conforms(to: .png) {
            return .png
        }
        if type.conforms(to: .heic) || type.conforms(to: .heif) {
            return .heif
        }
        return .unknown
    }

    package var supportsLossyQuality: Bool {
        switch self {
        case .jpeg, .heif:
            return true
        case .png, .unknown:
            return false
        }
    }
}
