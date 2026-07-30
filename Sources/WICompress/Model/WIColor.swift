//
//  WIColor.swift
//  WICompress
//
//  Created by weixi on 2026/6/27.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import CoreGraphics
import WIImageCore

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

extension WIColorSpace {
    var imageCoreValue: WIImageCore.ColorSpace {
        switch self {
        case .sRGB:
            return .sRGB
        case .displayP3:
            return .displayP3
        case .iccProfile(let data):
            return .iccProfile(data)
        }
    }

    func makeCGColorSpace() throws(WICompressError) -> CGColorSpace {
        do {
            return try imageCoreValue.makeCGColorSpace()
        } catch {
            switch error {
            case .invalidICCProfile:
                throw .invalidICCProfile
            case .unavailable, .unsupportedModel:
                throw .unsupportedColorSpace
            }
        }
    }
}

extension WIColor {
    var imageCoreValue: WIImageCore.Color {
        Color(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha,
            colorSpace: colorSpace.imageCoreValue
        )
    }
}
