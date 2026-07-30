//
//  ColorSpace.swift
//  WIImageCore
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation

package enum ColorSpaceError: Swift.Error, Sendable, Equatable {
    case unavailable
    case invalidICCProfile
    case unsupportedModel
}

package enum ColorSpace: Sendable, Equatable {
    case sRGB
    case displayP3
    case iccProfile(Data)

    package func makeCGColorSpace() throws(ColorSpaceError) -> CGColorSpace {
        let colorSpace: CGColorSpace
        switch self {
        case .sRGB:
            guard let resolved = CGColorSpace(name: CGColorSpace.sRGB) else {
                throw .unavailable
            }
            colorSpace = resolved
        case .displayP3:
            guard let resolved = CGColorSpace(name: CGColorSpace.displayP3) else {
                throw .unavailable
            }
            colorSpace = resolved
        case .iccProfile(let data):
            guard let resolved = CGColorSpace(iccData: data as CFData) else {
                throw .invalidICCProfile
            }
            colorSpace = resolved
        }

        guard colorSpace.model == .rgb else {
            throw .unsupportedModel
        }
        return colorSpace
    }
}
