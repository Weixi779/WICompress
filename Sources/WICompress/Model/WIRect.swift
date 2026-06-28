//
//  WIRect.swift
//  WICompress
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Floating-point rectangle used internally by render geometry plans.
struct WIRect: Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
