//
//  ImageFormat+ImageIO.swift
//  WIImageIO
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import WIImageCore

extension ImageFormat {
    package init(data: Data) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let typeIdentifier = CGImageSourceGetType(source)
        else {
            self = .unknown
            return
        }

        self.init(typeIdentifier: typeIdentifier as String)
    }

    package init(typeIdentifier: String?) {
        guard
            let typeIdentifier,
            let type = UTType(typeIdentifier)
        else {
            self = .unknown
            return
        }

        if type.conforms(to: .jpeg) {
            self = .jpeg
        } else if type.conforms(to: .png) {
            self = .png
        } else if type.conforms(to: .heic) || type.conforms(to: .heif) {
            self = .heif
        } else {
            self = .unknown
        }
    }
}
