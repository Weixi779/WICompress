//
//  WIImageResizing.swift
//  WICompressDomain
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

/// Resolves a complete source pixel size to a complete target pixel size.
public protocol WIImageResizing: Sendable {
    func targetSize(
        for sourceSize: WIPixelSize
    ) throws(WICompressError) -> WIPixelSize
}

/// Built-in resizing algorithms.
public struct WIImageResize: WIImageResizing, Sendable, Equatable {
    private enum Operation: Sendable, Equatable {
        case luban
        case maximumPixelSize(Int)
        case constrained(WIPixelSize, allowsUpscaling: Bool)
        case scaled(Double)
        case exact(WIPixelSize)
    }

    private let operation: Operation

    private init(operation: Operation) {
        self.operation = operation
    }

    /// Applies WICompress's Luban-derived proportional reduction.
    public static let luban = WIImageResize(operation: .luban)

    /// Caps the longest side without upscaling.
    public static func maximumPixelSize(_ value: Int) -> WIImageResize {
        WIImageResize(operation: .maximumPixelSize(max(value, 1)))
    }

    /// Scales proportionally within a two-dimensional pixel boundary.
    public static func constrained(
        within maximumSize: WIPixelSize,
        allowingUpscaling: Bool = false
    ) -> WIImageResize {
        WIImageResize(
            operation: .constrained(
                maximumSize,
                allowsUpscaling: allowingUpscaling
            )
        )
    }

    /// Applies an explicit proportional scale factor.
    public static func scaled(
        by factor: Double
    ) throws(WICompressError) -> WIImageResize {
        guard factor.isFinite, factor > 0 else {
            throw .invalidResizing
        }

        return WIImageResize(operation: .scaled(factor))
    }

    /// Returns an explicit target pixel size.
    public static func exact(_ size: WIPixelSize) -> WIImageResize {
        WIImageResize(operation: .exact(size))
    }

    public func targetSize(
        for sourceSize: WIPixelSize
    ) throws(WICompressError) -> WIPixelSize {
        switch operation {
        case .luban:
            let ratio = WILuban.ratio(
                width: sourceSize.width,
                height: sourceSize.height
            )
            guard ratio > 1 else {
                return sourceSize
            }

            let longSide = max(sourceSize.width, sourceSize.height)
            let maximumPixelSize = max(longSide / ratio, 1)
            return try constrainedSize(
                sourceSize,
                within: WIPixelSize(
                    width: maximumPixelSize,
                    height: maximumPixelSize
                ),
                allowsUpscaling: false
            )
        case .maximumPixelSize(let value):
            return try constrainedSize(
                sourceSize,
                within: WIPixelSize(width: value, height: value),
                allowsUpscaling: false
            )
        case .constrained(let maximumSize, let allowsUpscaling):
            return try constrainedSize(
                sourceSize,
                within: maximumSize,
                allowsUpscaling: allowsUpscaling
            )
        case .scaled(let factor):
            return try scaledSize(sourceSize, by: factor)
        case .exact(let size):
            return size
        }
    }

    private func constrainedSize(
        _ sourceSize: WIPixelSize,
        within maximumSize: WIPixelSize,
        allowsUpscaling: Bool
    ) throws(WICompressError) -> WIPixelSize {
        var factor = min(
            Double(maximumSize.width) / Double(sourceSize.width),
            Double(maximumSize.height) / Double(sourceSize.height)
        )
        if !allowsUpscaling {
            factor = min(factor, 1)
        }

        return try scaledSize(sourceSize, by: factor)
    }

    private func scaledSize(
        _ sourceSize: WIPixelSize,
        by factor: Double
    ) throws(WICompressError) -> WIPixelSize {
        guard
            let width = Int(
                exactly: (Double(sourceSize.width) * factor)
                    .rounded(.toNearestOrAwayFromZero)
            ),
            let height = Int(
                exactly: (Double(sourceSize.height) * factor)
                    .rounded(.toNearestOrAwayFromZero)
            )
        else {
            throw .invalidResizing
        }

        return WIPixelSize(
            width: max(width, 1),
            height: max(height, 1)
        )
    }
}
