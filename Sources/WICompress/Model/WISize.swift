//
//  WISize.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Width and height values used by WICompress policies.
public struct WISize: Sendable, Equatable {
    /// Width value.
    public var width: Double
    /// Height value.
    public var height: Double

    /// Creates a size value.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
