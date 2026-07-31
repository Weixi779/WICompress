//
//  WIImageCrop.swift
//  WICompressDomain
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

/// A normalized point used to bias an aspect-ratio crop.
public struct WICropAnchor: Sendable, Hashable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x.clamped(to: 0...1, fallback: 0.5)
        self.y = y.clamped(to: 0...1, fallback: 0.5)
    }

    public static let center = WICropAnchor(x: 0.5, y: 0.5)
}

/// A concrete width-to-height ratio.
public struct WIAspectRatio: Sendable, Hashable {
    public let width: Double
    public let height: Double

    public static let square = WIAspectRatio(
        validWidth: 1,
        height: 1
    )

    public init(
        width: Double,
        height: Double
    ) throws(WICompressError) {
        guard
            width.isFinite,
            height.isFinite,
            width > 0,
            height > 0,
            (width / height).isFinite,
            width / height > 0
        else {
            throw .invalidCrop
        }

        self.width = width
        self.height = height
    }

    private init(validWidth width: Double, height: Double) {
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
    ) throws(WICompressError) -> WIImageCrop {
        WIImageCrop(
            aspectRatio: try WIAspectRatio(width: width, height: height),
            anchor: anchor
        )
    }
}
