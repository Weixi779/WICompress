//
//  WIImageCrop.swift
//  WICompress
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// A normalized point used to bias an aspect-ratio crop.
public struct WICropAnchor: Sendable, Hashable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let center = WICropAnchor(x: 0.5, y: 0.5)
}

/// A concrete width-to-height ratio.
public struct WIAspectRatio: Sendable, Hashable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A concrete aspect-ratio crop resolved before resizing.
public struct WIImageCrop: Sendable, Hashable {
    public let aspectRatio: WIAspectRatio
    public let anchor: WICropAnchor

    public init(
        aspectRatio: WIAspectRatio,
        anchor: WICropAnchor = .center
    ) {
        self.aspectRatio = aspectRatio
        self.anchor = anchor
    }

    public static func aspectRatio(
        width: Double,
        height: Double,
        anchor: WICropAnchor = .center
    ) -> WIImageCrop {
        WIImageCrop(
            aspectRatio: WIAspectRatio(width: width, height: height),
            anchor: anchor
        )
    }
}
