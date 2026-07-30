//
//  Capabilities.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO

package enum Capabilities {
    package static func canDecode(typeIdentifier: String) -> Bool {
        readableTypeIdentifiers.contains(typeIdentifier)
    }

    package static func canEncode(typeIdentifier: String) -> Bool {
        writableTypeIdentifiers.contains(typeIdentifier)
    }

    private static let readableTypeIdentifiers: Set<String> = {
        guard let identifiers = CGImageSourceCopyTypeIdentifiers() as? [String] else {
            return []
        }

        return Set(identifiers)
    }()

    private static let writableTypeIdentifiers: Set<String> = {
        guard let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] else {
            return []
        }

        return Set(identifiers)
    }()
}
