//
//  Capabilities.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

package enum Capabilities {
    package static func canDecode(_ type: UTType) -> Bool {
        readableTypes.contains(type)
    }

    package static func canEncode(_ type: UTType) -> Bool {
        writableTypes.contains(type)
    }

    private static let readableTypes: Set<UTType> = {
        guard let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] else {
            return []
        }

        return Set(identifiers.compactMap(UTType.init))
    }()

    private static let writableTypes: Set<UTType> = {
        guard let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] else {
            return []
        }

        return Set(identifiers.compactMap(UTType.init))
    }()
}
