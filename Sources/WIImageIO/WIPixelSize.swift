//
//  WIPixelSize.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

package struct WIPixelSize: Sendable, Hashable {
    package let width: Int
    package let height: Int
    package let pixelCount: Int

    package init(width: Int, height: Int) throws(WIImageIOError) {
        guard width > 0, height > 0 else {
            throw .invalidPixelSize(width: width, height: height)
        }

        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw .pixelCountOverflow(width: width, height: height)
        }

        self.width = width
        self.height = height
        self.pixelCount = pixelCount
    }
}
