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
    package enum ValidationError: Swift.Error, Sendable, Equatable {
        case invalidDimensions(width: Int, height: Int)
        case pixelCountOverflow(width: Int, height: Int)
    }

    public let width: Int
    public let height: Int

    package var pixelCount: Int {
        width * height
    }

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    package init(
        validatingWidth width: Int,
        height: Int
    ) throws(ValidationError) {
        guard width > 0, height > 0 else {
            throw .invalidDimensions(width: width, height: height)
        }

        let (_, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw .pixelCountOverflow(width: width, height: height)
        }

        self.init(width: width, height: height)
    }
}
