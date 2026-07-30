//
//  ImageFormat.swift
//  WIImageCore
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

package enum ImageFormat: Sendable, Equatable {
    case jpeg
    case png
    case heif
    case unknown

    package var supportsLossyQuality: Bool {
        switch self {
        case .jpeg, .heif:
            return true
        case .png, .unknown:
            return false
        }
    }
}
