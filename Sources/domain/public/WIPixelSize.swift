//
//  WIPixelSize.swift
//  WIImageDomain
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
        self.width = max(width, 1)
        self.height = max(height, 1)
    }

    package init(validWidth width: Int, height: Int) {
        precondition(width > 0 && height > 0)
        precondition(!width.multipliedReportingOverflow(by: height).overflow)

        self.width = width
        self.height = height
    }
}
