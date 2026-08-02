//
//  BitmapCanvas.swift
//  WIImageRendering
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import WIImageDomain

final class BitmapCanvas {
    private let context: CGContext
    private let colorSpace: CGColorSpace
    private let bounds: CGRect

    // MARK: - Initialization

    init(
        size: WIPixelSize,
        alphaMode: ImageAlphaMode,
        colorSpace: CGColorSpace
    ) throws(ImageRenderingError) {
        try Self.preflightBitmapMemory(for: size)

        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: alphaMode.bitmapInfo
        ) else {
            throw .contextCreationFailed
        }

        self.context = context
        self.colorSpace = colorSpace
        self.bounds = CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: size.height
        )

        context.clear(bounds)
        context.interpolationQuality = .high
        context.setRenderingIntent(.relativeColorimetric)
    }

    // MARK: - Drawing

    func fill(_ color: WIColor) throws(ImageRenderingError) {
        context.setFillColor(try color.cgColor(in: colorSpace))
        context.fill(bounds)
    }

    func fill(_ color: WIColor, in rect: Rect) throws(ImageRenderingError) {
        let fillBounds = bottomLeftRect(rect)
        guard fillBounds.hasFiniteGeometry else {
            throw .invalidDestinationRect
        }

        context.setFillColor(try color.cgColor(in: colorSpace))
        context.fill(fillBounds)
    }

    func draw(
        _ image: CGImage,
        sourceRect: Rect,
        destinationRect: Rect,
        orientation: WIImageOrientation
    ) throws(ImageRenderingError) {
        let destinationBounds = bottomLeftRect(destinationRect)
        guard destinationBounds.hasFiniteGeometry else {
            throw .invalidDestinationRect
        }

        let storedPixelSize = WIPixelSize(
            validWidth: image.width,
            height: image.height
        )
        let orientedPixelSize = storedPixelSize.oriented(by: orientation)
        let scaleX = destinationRect.width / sourceRect.width
        let scaleY = destinationRect.height / sourceRect.height
        let fullImageRect = Rect(
            x: destinationRect.x - sourceRect.x * scaleX,
            y: destinationRect.y - sourceRect.y * scaleY,
            width: Double(orientedPixelSize.width) * scaleX,
            height: Double(orientedPixelSize.height) * scaleY
        )
        guard fullImageRect.isFiniteAndPositive else {
            throw .invalidDestinationRect
        }
        let fullImageBounds = bottomLeftRect(fullImageRect)
        guard fullImageBounds.hasFiniteGeometry else {
            throw .invalidDestinationRect
        }

        context.saveGState()
        defer { context.restoreGState() }

        context.clip(to: destinationBounds)
        context.translateBy(x: fullImageBounds.minX, y: fullImageBounds.minY)
        context.scaleBy(
            x: fullImageBounds.width / Double(orientedPixelSize.width),
            y: fullImageBounds.height / Double(orientedPixelSize.height)
        )
        context.apply(
            orientation,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: image.width,
                height: image.height
            )
        )
    }

    // MARK: - Output

    func image() throws(ImageRenderingError) -> CGImage {
        guard let image = context.makeImage() else {
            throw .imageCreationFailed
        }

        return image
    }

    // MARK: - Private

    private func bottomLeftRect(_ rect: Rect) -> CGRect {
        CGRect(
            x: rect.x,
            y: Double(bounds.height) - rect.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func preflightBitmapMemory(for size: WIPixelSize) throws(ImageRenderingError) {
        let (minimumRowBytes, rowOverflow) = size.width.multipliedReportingOverflow(by: 4)
        guard !rowOverflow else {
            throw .rowByteOverflow(width: size.width)
        }

        let (alignmentInput, alignmentOverflow) = minimumRowBytes.addingReportingOverflow(63)
        guard !alignmentOverflow else {
            throw .rowByteOverflow(width: size.width)
        }

        let alignedRowBytes = (alignmentInput / 64) * 64
        let (_, totalOverflow) = alignedRowBytes.multipliedReportingOverflow(by: size.height)
        guard !totalOverflow else {
            throw .bitmapByteCountOverflow(
                width: size.width,
                height: size.height
            )
        }
    }
}

private extension ImageAlphaMode {
    var bitmapInfo: UInt32 {
        switch self {
        case .opaque:
            return CGImageAlphaInfo.noneSkipLast.rawValue
        case .preserve:
            return CGImageAlphaInfo.premultipliedLast.rawValue
        }
    }
}

private extension WIColor {
    func cgColor(in destinationColorSpace: CGColorSpace) throws(ImageRenderingError) -> CGColor {
        let sourceColorSpace: CGColorSpace
        do {
            sourceColorSpace = try colorSpace.makeCGColorSpace()
        } catch {
            switch error {
            case .invalidICCProfile:
                throw .invalidICCProfile
            case .unavailable, .unsupportedModel:
                throw .unsupportedColorSpace
            }
        }

        let components = [
            red.clamped,
            green.clamped,
            blue.clamped,
            alpha.clamped
        ]
        guard
            let sourceColor = CGColor(
                colorSpace: sourceColorSpace,
                components: components
            ),
            let destinationColor = sourceColor.converted(
                to: destinationColorSpace,
                intent: .relativeColorimetric,
                options: nil
            )
        else {
            throw .colorConversionFailed
        }

        return destinationColor
    }
}

private extension CGContext {
    func apply(
        _ orientation: WIImageOrientation,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        let width = CGFloat(pixelWidth)
        let height = CGFloat(pixelHeight)

        switch orientation {
        case .up:
            break
        case .upMirrored:
            translateBy(x: width, y: 0)
            scaleBy(x: -1, y: 1)
        case .down:
            translateBy(x: width, y: height)
            rotate(by: .pi)
        case .downMirrored:
            translateBy(x: 0, y: height)
            scaleBy(x: 1, y: -1)
        case .leftMirrored:
            translateBy(x: height, y: 0)
            scaleBy(x: -1, y: 1)
            translateBy(x: 0, y: width)
            rotate(by: -.pi / 2)
        case .right:
            translateBy(x: 0, y: width)
            rotate(by: -.pi / 2)
        case .rightMirrored:
            translateBy(x: height, y: 0)
            scaleBy(x: -1, y: 1)
            translateBy(x: height, y: 0)
            rotate(by: .pi / 2)
        case .left:
            translateBy(x: height, y: 0)
            rotate(by: .pi / 2)
        }
    }
}

private extension Rect {
    var isFiniteAndPositive: Bool {
        x.isFinite &&
        y.isFinite &&
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0
    }
}

private extension CGRect {
    var hasFiniteGeometry: Bool {
        origin.x.isFinite &&
        origin.y.isFinite &&
        width.isFinite &&
        height.isFinite
    }
}

private extension Double {
    var clamped: CGFloat {
        guard isFinite else {
            return 0
        }

        return CGFloat(min(max(self, 0), 1))
    }
}
