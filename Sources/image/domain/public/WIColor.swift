//
//  WIColor.swift
//  WIImageDomain
//
//  Created by weixi on 2026/6/27.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import CoreGraphics

/// Concrete color space used by image output and color values.
public enum WIColorSpace: Sendable, Hashable {
    /// Standard sRGB color space.
    case sRGB
    /// Display P3 wide-gamut RGB color space.
    case displayP3
    /// A caller-supplied ICC profile.
    case iccProfile(Data)
}

/// RGB color value with an explicit color space.
public struct WIColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public var colorSpace: WIColorSpace

    /// Creates an RGB color in the supplied color space.
    public init(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1,
        colorSpace: WIColorSpace = .sRGB
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.colorSpace = colorSpace
    }
}

package enum ColorSpaceError: Swift.Error, Sendable, Equatable {
    case unavailable
    case invalidICCProfile
    case unsupportedModel
}

extension WIColorSpace {
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
