//
//  WIImageColorSpace.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

package enum WIImageColorSpace: Sendable, Equatable {
    case sRGB
    case displayP3
    case iccProfile(Data)
}
