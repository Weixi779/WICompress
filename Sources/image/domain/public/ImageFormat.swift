//
//  ImageFormat.swift
//  WIImageDomain
//
//  Created by weixi on 2026/7/31.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import UniformTypeIdentifiers

/// Recognized image container families.
public enum ImageFormat: Sendable, Equatable {
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

    package var supportsLossyQuality: Bool {
        switch self {
        case .jpeg, .heif:
            return true
        case .png, .unknown:
            return false
        }
    }

    package static func detected(from type: UTType?) -> Self {
        guard let type else {
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
}
