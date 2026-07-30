//
//  WIPixelSize.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// A two-dimensional size measured in pixels.
public struct WIPixelSize: Sendable, Hashable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init(_ size: WISize) {
        self.init(
            width: max(Int(size.width.rounded(.toNearestOrAwayFromZero)), 1),
            height: max(Int(size.height.rounded(.toNearestOrAwayFromZero)), 1)
        )
    }
}
