//
//  WIQualityPolicy.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Lossy compression quality policy.
public enum WIQualityPolicy: Sendable, Equatable {
    /// Do not set an explicit lossy quality value.
    case none
    /// Set lossy quality for destination formats that support it.
    case compression(Double)
}
