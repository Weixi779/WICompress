//
//  Orientation.swift
//  WIImageCore
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

package enum Orientation: Int, Sendable, Equatable, CaseIterable {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8

    package var swapsDimensions: Bool {
        switch self {
        case .leftMirrored, .right, .rightMirrored, .left:
            return true
        case .up, .upMirrored, .down, .downMirrored:
            return false
        }
    }
}
