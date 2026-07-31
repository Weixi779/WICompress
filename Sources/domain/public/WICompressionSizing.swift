//
//  WICompressionSizing.swift
//  WIImageDomain
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Base pixel constraints resolved before target byte search begins.
public struct WICompressionSizing: Sendable, Hashable {
    /// Optional upper bound for the base candidate's longest pixel side.
    public let maximumPixelSize: Int?
    /// Optional concrete output aspect ratio.
    public let aspectRatio: WIAspectRatio?
    /// Normalized top-left-origin anchor used by the aspect-ratio crop.
    public let anchor: WICropAnchor

    public init(
        maximumPixelSize: Int? = nil,
        aspectRatio: WIAspectRatio? = nil,
        anchor: WICropAnchor = .center
    ) {
        self.maximumPixelSize = maximumPixelSize
        self.aspectRatio = aspectRatio
        self.anchor = anchor
    }
}
