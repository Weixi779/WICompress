//
//  WIColorSpacePolicy.swift
//  WICompress
//
//  Created by weixi on 2026/6/27.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import CoreGraphics

/// Output color-space target used by color-space policies.
public enum WIColorSpace: Sendable, Hashable {
    /// Standard sRGB color space.
    case sRGB
    /// Display P3 wide-gamut RGB color space.
    case displayP3
    /// A caller-supplied ICC profile.
    case iccProfile(Data)
}

/// Output color-space handling policy.
public enum WIOutputColorSpace: Sendable, Equatable {
    /// Preserve normal source display semantics.
    case preserve
    /// Convert output pixels to a target color space.
    case convert(to: WIColorSpace)
    /// Preserve supported source spaces, otherwise convert to a fallback.
    case preserveIfSupported(Set<WIColorSpace>, otherwise: WIColorSpace)
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

extension WIColorSpace {
    func makeCGColorSpace() throws(WICompressError) -> CGColorSpace {
        switch self {
        case .sRGB:
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                throw WICompressError.unsupportedColorSpace
            }

            return colorSpace
        case .displayP3:
            guard let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) else {
                throw WICompressError.unsupportedColorSpace
            }

            return colorSpace
        case .iccProfile(let data):
            guard let colorSpace = CGColorSpace(iccData: data as CFData) else {
                throw WICompressError.invalidICCProfile
            }

            return colorSpace
        }
    }
}
