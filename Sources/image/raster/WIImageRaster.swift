//
//  WIImageRaster.swift
//  WIImageRaster
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import WIImageDomain

package enum WIImageRaster {
    package static func image(
        _ sourceImage: CGImage,
        plan: Plan
    ) throws(Error) -> CGImage {
        try validate(plan, sourceImage: sourceImage)
        try preflightBitmapMemory(for: plan.canvasSize)

        let colorSpace = try resolvedColorSpace(
            plan.colorSpace,
            sourceColorSpace: sourceImage.colorSpace
        )
        let bitmapInfo = bitmapInfo(alphaMode: plan.alphaMode)
        guard let context = CGContext(
            data: nil,
            width: plan.canvasSize.width,
            height: plan.canvasSize.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw .contextCreationFailed
        }

        let canvasRect = CGRect(
            x: 0,
            y: 0,
            width: plan.canvasSize.width,
            height: plan.canvasSize.height
        )
        let destinationRect = bottomLeftRect(
            plan.destinationRect,
            canvasHeight: Double(plan.canvasSize.height)
        )
        guard destinationRect.hasFiniteGeometry else {
            throw .invalidDestinationRect
        }

        context.clear(canvasRect)
        context.interpolationQuality = .high
        context.setRenderingIntent(.relativeColorimetric)

        if let background = plan.canvasBackground {
            context.setFillColor(try cgColor(background, in: colorSpace))
            context.fill(canvasRect)
        }

        if let background = plan.imageBackground {
            context.setFillColor(try cgColor(background, in: colorSpace))
            context.fill(destinationRect)
        }

        let orientedWidth = plan.orientation.swapsDimensions
            ? sourceImage.height
            : sourceImage.width
        let orientedHeight = plan.orientation.swapsDimensions
            ? sourceImage.width
            : sourceImage.height
        let sourceRect = plan.sourceRect
        let scaleX = plan.destinationRect.width / sourceRect.width
        let scaleY = plan.destinationRect.height / sourceRect.height
        let fullImageRect = Rect(
            x: plan.destinationRect.x - sourceRect.x * scaleX,
            y: plan.destinationRect.y - sourceRect.y * scaleY,
            width: Double(orientedWidth) * scaleX,
            height: Double(orientedHeight) * scaleY
        )
        guard fullImageRect.isFiniteAndPositive else {
            throw .invalidDestinationRect
        }
        let fullImageBottomLeftRect = bottomLeftRect(
            fullImageRect,
            canvasHeight: Double(plan.canvasSize.height)
        )
        guard fullImageBottomLeftRect.hasFiniteGeometry else {
            throw .invalidDestinationRect
        }

        context.saveGState()
        context.clip(to: destinationRect)
        context.translateBy(
            x: fullImageBottomLeftRect.minX,
            y: fullImageBottomLeftRect.minY
        )
        context.scaleBy(
            x: fullImageBottomLeftRect.width / Double(orientedWidth),
            y: fullImageBottomLeftRect.height / Double(orientedHeight)
        )
        applyOrientationTransform(
            to: context,
            orientation: plan.orientation,
            pixelWidth: sourceImage.width,
            pixelHeight: sourceImage.height
        )
        context.draw(
            sourceImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: sourceImage.width,
                height: sourceImage.height
            )
        )
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw .imageCreationFailed
        }

        return image
    }

    private static func validate(
        _ plan: Plan,
        sourceImage: CGImage
    ) throws(Error) {
        guard plan.sourceRect.isFiniteAndPositive else {
            throw .invalidSourceRect
        }
        guard plan.destinationRect.isFiniteAndPositive else {
            throw .invalidDestinationRect
        }

        let orientedWidth = plan.orientation.swapsDimensions
            ? sourceImage.height
            : sourceImage.width
        let orientedHeight = plan.orientation.swapsDimensions
            ? sourceImage.width
            : sourceImage.height
        guard
            plan.sourceRect.x >= 0,
            plan.sourceRect.y >= 0,
            plan.sourceRect.x + plan.sourceRect.width <= Double(orientedWidth),
            plan.sourceRect.y + plan.sourceRect.height <= Double(orientedHeight)
        else {
            throw .sourceRectOutOfBounds
        }

        if let background = plan.canvasBackground,
           !background.alpha.isFinite || background.alpha < 1 {
            throw .nonOpaqueBackground
        }
        if let background = plan.imageBackground,
           !background.alpha.isFinite || background.alpha < 1 {
            throw .nonOpaqueBackground
        }
    }

    private static func preflightBitmapMemory(
        for size: WIPixelSize
    ) throws(Error) {
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
            throw .bitmapByteCountOverflow(width: size.width, height: size.height)
        }
    }

    private static func resolvedColorSpace(
        _ colorSpace: OutputColorSpace,
        sourceColorSpace: CGColorSpace?
    ) throws(Error) -> CGColorSpace {
        switch colorSpace {
        case .source:
            guard
                let sourceColorSpace,
                sourceColorSpace.model == .rgb
            else {
                return CGColorSpaceCreateDeviceRGB()
            }

            return sourceColorSpace
        case .convert(let target):
            return try makeCGColorSpace(target)
        }
    }

    private static func makeCGColorSpace(
        _ colorSpace: WIColorSpace
    ) throws(Error) -> CGColorSpace {
        do {
            return try colorSpace.makeCGColorSpace()
        } catch {
            switch error {
            case .invalidICCProfile:
                throw .invalidICCProfile
            case .unavailable, .unsupportedModel:
                throw .unsupportedColorSpace
            }
        }
    }

    private static func cgColor(
        _ color: WIColor,
        in destinationColorSpace: CGColorSpace
    ) throws(Error) -> CGColor {
        let sourceColorSpace = try makeCGColorSpace(color.colorSpace)
        let components = [
            clamped(color.red),
            clamped(color.green),
            clamped(color.blue),
            clamped(color.alpha)
        ]
        guard
            let sourceColor = CGColor(colorSpace: sourceColorSpace, components: components),
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

    private static func bitmapInfo(
        alphaMode: AlphaMode
    ) -> UInt32 {
        switch alphaMode {
        case .opaque:
            return CGImageAlphaInfo.noneSkipLast.rawValue
        case .preserve:
            return CGImageAlphaInfo.premultipliedLast.rawValue
        }
    }

    private static func applyOrientationTransform(
        to context: CGContext,
        orientation: WIImageOrientation,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        let width = CGFloat(pixelWidth)
        let height = CGFloat(pixelHeight)

        switch orientation {
        case .up:
            break
        case .upMirrored:
            context.translateBy(x: width, y: 0)
            context.scaleBy(x: -1, y: 1)
        case .down:
            context.translateBy(x: width, y: height)
            context.rotate(by: .pi)
        case .downMirrored:
            context.translateBy(x: 0, y: height)
            context.scaleBy(x: 1, y: -1)
        case .leftMirrored:
            context.translateBy(x: height, y: 0)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: 0, y: width)
            context.rotate(by: -.pi / 2)
        case .right:
            context.translateBy(x: 0, y: width)
            context.rotate(by: -.pi / 2)
        case .rightMirrored:
            context.translateBy(x: height, y: 0)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: height, y: 0)
            context.rotate(by: .pi / 2)
        case .left:
            context.translateBy(x: height, y: 0)
            context.rotate(by: .pi / 2)
        }
    }

    private static func bottomLeftRect(
        _ rect: Rect,
        canvasHeight: Double
    ) -> CGRect {
        CGRect(
            x: rect.x,
            y: canvasHeight - rect.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func clamped(_ value: Double) -> CGFloat {
        guard value.isFinite else {
            return 0
        }

        return CGFloat(min(max(value, 0), 1))
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
