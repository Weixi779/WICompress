//
//  WIImageRenderingTests.swift
//  WIImageRenderingTests
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import WIImageDomain
@testable import WIImageRendering

extension Tag {
    @Tag static var imageRenderingCore: Self
}

@Suite("WIImageRendering", .tags(.imageRenderingCore))
struct WIImageRenderingTests {
    private struct Pixel: Equatable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8
    }

    @Test("Invalid and out-of-bounds rects are rejected")
    func invalidRectsAreRejected() throws {
        let image = try #require(Self.verticalBands(width: 4, height: 4))
        let invalidSource = ImageRenderRequest(
            canvasSize: WIPixelSize(width: 4, height: 4),
            sourceRect: Rect(x: 0, y: 0, width: 0, height: 4),
            destinationRect: Rect(x: 0, y: 0, width: 4, height: 4)
        )
        let invalidDestination = ImageRenderRequest(
            canvasSize: WIPixelSize(width: 4, height: 4),
            sourceRect: Rect(x: 0, y: 0, width: 4, height: 4),
            destinationRect: Rect(
                x: 0,
                y: 0,
                width: .infinity,
                height: 4
            )
        )
        let outOfBoundsSource = ImageRenderRequest(
            canvasSize: WIPixelSize(width: 4, height: 4),
            sourceRect: Rect(x: 3, y: 0, width: 2, height: 4),
            destinationRect: Rect(x: 0, y: 0, width: 4, height: 4)
        )

        #expect(throws: ImageRenderingError.invalidSourceRect) {
            try ImageRenderer.render(image, request: invalidSource)
        }
        #expect(throws: ImageRenderingError.invalidDestinationRect) {
            try ImageRenderer.render(image, request: invalidDestination)
        }
        #expect(throws: ImageRenderingError.sourceRectOutOfBounds) {
            try ImageRenderer.render(image, request: outOfBoundsSource)
        }
    }

    @Test("Bitmap byte arithmetic rejects overflow")
    func bitmapByteArithmeticRejectsOverflow() throws {
        let image = try #require(Self.verticalBands(width: 1, height: 1))
        let rowOverflow = ImageRenderRequest(
            canvasSize: WIPixelSize(width: .max, height: 1),
            sourceRect: Rect(x: 0, y: 0, width: 1, height: 1),
            destinationRect: Rect(x: 0, y: 0, width: 1, height: 1)
        )
        let totalOverflow = ImageRenderRequest(
            canvasSize: WIPixelSize(width: 1, height: .max),
            sourceRect: Rect(x: 0, y: 0, width: 1, height: 1),
            destinationRect: Rect(x: 0, y: 0, width: 1, height: 1)
        )

        #expect(throws: ImageRenderingError.rowByteOverflow(width: .max)) {
            try ImageRenderer.render(image, request: rowOverflow)
        }
        #expect(
            throws: ImageRenderingError.bitmapByteCountOverflow(
                width: 1,
                height: .max
            )
        ) {
            try ImageRenderer.render(image, request: totalOverflow)
        }
    }

    @Test("Background colors must be opaque")
    func backgroundsMustBeOpaque() throws {
        let image = try #require(Self.verticalBands(width: 1, height: 1))
        let request = ImageRenderRequest(
            canvasSize: WIPixelSize(width: 1, height: 1),
            sourceRect: Rect(x: 0, y: 0, width: 1, height: 1),
            destinationRect: Rect(x: 0, y: 0, width: 1, height: 1),
            canvasBackground: WIColor(
                red: 0,
                green: 0,
                blue: 0,
                alpha: 0.5
            )
        )

        #expect(throws: ImageRenderingError.nonOpaqueBackground) {
            try ImageRenderer.render(image, request: request)
        }
    }

    @Test("Source crop is resolved in oriented top-left coordinates")
    func sourceCropUsesTopLeftCoordinates() throws {
        let source = try #require(Self.verticalBands(width: 8, height: 4))
        let output = try ImageRenderer.render(
            source,
            request: ImageRenderRequest(
                canvasSize: WIPixelSize(width: 4, height: 4),
                sourceRect: Rect(x: 2, y: 0, width: 4, height: 4),
                destinationRect: Rect(x: 0, y: 0, width: 4, height: 4)
            )
        )

        #expect(try Self.pixel(output, x: 0, y: 0) == Self.pixel(source, x: 2, y: 0))
        #expect(try Self.pixel(output, x: 3, y: 3) == Self.pixel(source, x: 5, y: 3))
    }

    @Test("Canvas and image backgrounds remain independent")
    func canvasAndImageBackgroundsRemainIndependent() throws {
        let source = try #require(Self.transparentImage(width: 2, height: 2))
        let output = try ImageRenderer.render(
            source,
            request: ImageRenderRequest(
                canvasSize: WIPixelSize(width: 4, height: 4),
                sourceRect: Rect(x: 0, y: 0, width: 2, height: 2),
                destinationRect: Rect(x: 1, y: 1, width: 2, height: 2),
                alphaMode: .opaque,
                canvasBackground: WIColor(red: 0, green: 1, blue: 0),
                imageBackground: WIColor(red: 1, green: 1, blue: 1),
                colorSpace: .sRGB
            )
        )

        let canvasPixel = try Self.pixel(output, x: 0, y: 0)
        let imagePixel = try Self.pixel(output, x: 2, y: 2)

        #expect(canvasPixel.green > 250)
        #expect(canvasPixel.red < 5)
        #expect(imagePixel.red > 250)
        #expect(imagePixel.green > 250)
        #expect(imagePixel.blue > 250)
    }

    @Test("Preserve alpha keeps opaque-source padding transparent")
    func preserveAlphaKeepsOpaqueSourcePaddingTransparent() throws {
        let source = try #require(Self.verticalBands(width: 2, height: 2))
        let output = try ImageRenderer.render(
            source,
            request: ImageRenderRequest(
                canvasSize: WIPixelSize(width: 4, height: 4),
                sourceRect: Rect(x: 0, y: 0, width: 2, height: 2),
                destinationRect: Rect(x: 1, y: 1, width: 2, height: 2),
                alphaMode: .preserve
            )
        )

        #expect(try Self.pixel(output, x: 0, y: 0).alpha == 0)
        #expect(try Self.pixel(output, x: 2, y: 2).alpha == 255)
    }

    @Test(
        "WIImageOrientation rendering matches the ImageIO display transform",
        arguments: WIImageOrientation.allCases
    )
    func orientationMatchesImageIO(
        _ orientation: WIImageOrientation
    ) throws {
        let data = try Self.quadrantJPEG(
            width: 8,
            height: 4,
            orientation: orientation.rawValue
        )
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let rawImage = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let oracle = try #require(
            CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 8
                ] as CFDictionary
            )
        )
        let swapsDimensions = [5, 6, 7, 8].contains(orientation.rawValue)
        let displayWidth = swapsDimensions ? 4 : 8
        let displayHeight = swapsDimensions ? 8 : 4
        let output = try ImageRenderer.render(
            rawImage,
            request: ImageRenderRequest(
                canvasSize: WIPixelSize(
                    width: displayWidth,
                    height: displayHeight
                ),
                sourceRect: Rect(
                    x: 0,
                    y: 0,
                    width: Double(displayWidth),
                    height: Double(displayHeight)
                ),
                destinationRect: Rect(
                    x: 0,
                    y: 0,
                    width: Double(displayWidth),
                    height: Double(displayHeight)
                ),
                orientation: orientation,
                colorSpace: .sRGB
            )
        )

        try #require(output.width == oracle.width)
        try #require(output.height == oracle.height)
        #expect(try Self.maximumRGBDifference(output, oracle) < 48)
    }

    private static func verticalBands(width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * bytesPerRow + x * 4
                pixels[index] = UInt8(x * 24)
                pixels[index + 1] = UInt8(y * 32)
                pixels[index + 2] = 80
                pixels[index + 3] = 255
            }
        }

        return image(width: width, height: height, pixels: pixels)
    }

    private static func transparentImage(width: Int, height: Int) -> CGImage? {
        image(
            width: width,
            height: height,
            pixels: [UInt8](repeating: 0, count: width * height * 4)
        )
    }

    private static func image(
        width: Int,
        height: Int,
        pixels: [UInt8]
    ) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func quadrantJPEG(
        width: Int,
        height: Int,
        orientation: Int
    ) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        let halfWidth = CGFloat(width) / 2
        let halfHeight = CGFloat(height) / 2
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight))

        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                data,
                "public.jpeg" as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func pixel(
        _ image: CGImage,
        x: Int,
        y: Int
    ) throws -> Pixel {
        let pixels = try rgbaPixels(image)
        let bytesPerRow = image.width * 4
        let index = y * bytesPerRow + x * 4
        return Pixel(
            red: pixels[index],
            green: pixels[index + 1],
            blue: pixels[index + 2],
            alpha: pixels[index + 3]
        )
    }

    private static func maximumRGBDifference(
        _ lhs: CGImage,
        _ rhs: CGImage
    ) throws -> Int {
        let lhsPixels = try rgbaPixels(lhs)
        let rhsPixels = try rgbaPixels(rhs)
        var maximumDifference = 0

        for index in lhsPixels.indices where index % 4 != 3 {
            maximumDifference = max(
                maximumDifference,
                abs(Int(lhsPixels[index]) - Int(rhsPixels[index]))
            )
        }

        return maximumDifference
    }

    private static func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo
                )
            )
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        }

        return pixels
    }
}
