//
//  WICompressionTargetValidator.swift
//  WICompressExecution
//
//  Created by weixi on 2026/6/28.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

/// Validates target facts that do not depend on source image inspection.
enum WICompressionTargetValidator {
    static func validate(_ target: WICompressionTarget) throws(WICompressError) {
        guard target.maxBytes > 0 else {
            throw WICompressError.invalidTarget
        }

        if let maximumPixelSize = target.sizing.maximumPixelSize,
           maximumPixelSize <= 0 {
            throw WICompressError.invalidTarget
        }

        if let aspectRatio = target.sizing.aspectRatio {
            let anchor = target.sizing.anchor
            guard
                aspectRatio.width.isFinite,
                aspectRatio.height.isFinite,
                aspectRatio.width > 0,
                aspectRatio.height > 0,
                anchor.x.isFinite,
                anchor.y.isFinite,
                (0...1).contains(anchor.x),
                (0...1).contains(anchor.y)
            else {
                throw WICompressError.invalidTarget
            }
        } else if target.sizing.anchor != .center {
            throw WICompressError.invalidTarget
        }
    }
}
