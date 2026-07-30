//
//  PixelSize.swift
//  WIImageCore
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

package struct PixelSize: Sendable, Hashable {
    package enum ValidationError: Swift.Error, Sendable, Equatable {
        case invalidDimensions(width: Int, height: Int)
        case pixelCountOverflow(width: Int, height: Int)
    }

    package let width: Int
    package let height: Int

    package var pixelCount: Int {
        width * height
    }

    package init(
        width: Int,
        height: Int
    ) throws(ValidationError) {
        guard width > 0, height > 0 else {
            throw .invalidDimensions(width: width, height: height)
        }

        let (_, overflow) = width.multipliedReportingOverflow(
            by: height
        )
        guard !overflow else {
            throw .pixelCountOverflow(width: width, height: height)
        }

        self.width = width
        self.height = height
    }
}
