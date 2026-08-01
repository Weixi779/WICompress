//
//  ImageMetadataOptions.swift
//  WIImageDomain
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Metadata categories retained in encoded output.
public struct ImageMetadataOptions: OptionSet, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Exif and Exif auxiliary metadata.
    public static let exif = Self(rawValue: 1 << 0)
    /// Standard GPS metadata exposed by ImageIO.
    public static let gps = Self(rawValue: 1 << 1)
    /// IPTC descriptive metadata.
    public static let iptc = Self(rawValue: 1 << 2)
    /// TIFF metadata excluding display orientation.
    public static let tiff = Self(rawValue: 1 << 3)
    /// Camera-vendor maker metadata supported by ImageIO.
    public static let makerNotes = Self(rawValue: 1 << 4)

    /// All metadata categories supported by WICompress.
    public static let all: Self = [
        .exif,
        .gps,
        .iptc,
        .tiff,
        .makerNotes
    ]

    /// Strip all supported non-display metadata.
    public static let strip: Self = []
    /// Preserve all supported metadata.
    public static let preserve: Self = .all

    package var preservesUnmodeledMetadata: Bool {
        self == .preserve || self == .preserve.subtracting(.gps)
    }
}
