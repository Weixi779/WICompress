//
//  WIImageFormat.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

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
        guard
            let typeIdentifier,
            let type = UTType(typeIdentifier)
        else {
            self = .unknown
            return
        }

        if type.conforms(to: .jpeg) {
            self = .jpeg
        } else if type.conforms(to: .png) {
            self = .png
        } else if type.conforms(to: .heic) || type.conforms(to: .heif) {
            self = .heif
        } else {
            self = .unknown
        }
    }

    var supportsLossyQuality: Bool {
        switch self {
        case .jpeg, .heif:
            return true
        case .png, .unknown:
            return false
        }
    }

    /// Detects the image format from container bytes.
    public init(data: Data) {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let uti = CGImageSourceGetType(imageSource)
        else {
            self = .unknown
            return
        }

        self.init(typeIdentifier: uti as String)
    }
}
