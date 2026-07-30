//
//  Rect.swift
//  WIImageDomain
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

package struct Rect: Sendable, Equatable {
    package let x: Double
    package let y: Double
    package let width: Double
    package let height: Double

    package init(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
