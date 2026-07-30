//
//  Color.swift
//  WIImageCore
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

package struct Color: Sendable, Equatable {
    package let red: Double
    package let green: Double
    package let blue: Double
    package let alpha: Double
    package let colorSpace: ColorSpace

    package init(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1,
        colorSpace: ColorSpace = .sRGB
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.colorSpace = colorSpace
    }
}
