//
//  WILuban.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

enum WILuban {
    static func ensureEven(_ size: Int) -> Int {
        return size % 2 != 0 ? size + 1 : size
    }

    static func ratio(width: Int, height: Int) -> Int {
        let longSide = max(ensureEven(width), ensureEven(height))
        let shortSide = min(ensureEven(width), ensureEven(height))
        let aspectRatio = Double(shortSide) / Double(longSide)

        switch aspectRatio {
        case 0.5625...1 where longSide < 1664:
            return 1
        case 0.5625...1 where longSide < 4990:
            return 2
        case 0.5625...1 where longSide < 10240:
            return 4
        case 0.5625...1:
            return max(longSide / 1280, 1)
        case 0.5..<0.5625:
            return longSide > 1280 ? max(longSide / 1280, 1) : 1
        default:
            // Original Luban uses `ceil(longSide / (1280 / scale))` where
            // `scale = shortSide / longSide`, which simplifies to
            // `ceil(shortSide / 1280)`. Dividing the long side here over-shrinks
            // very long images (e.g. panoramas / long screenshots).
            return max(Int(ceil(Double(shortSide) / 1280.0)), 1)
        }
    }
}
