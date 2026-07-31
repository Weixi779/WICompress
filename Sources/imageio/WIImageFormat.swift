//
//  WIImageFormat.swift
//  WIImageIO
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import UniformTypeIdentifiers
import WIImageDomain

extension WIImageFormat {
    package static func detected(from type: UTType?) -> Self {
        guard let type else {
            return .unknown
        }

        if type.conforms(to: .jpeg) {
            return .jpeg
        }
        if type.conforms(to: .png) {
            return .png
        }
        if type.conforms(to: .heic) || type.conforms(to: .heif) {
            return .heif
        }
        return .unknown
    }

}
