//
//  WIPixelSize.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Integer pixel size used internally by rendering and encoding plans.
struct WIPixelSize: Sendable, Equatable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
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
