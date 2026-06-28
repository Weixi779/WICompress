//
//  WICompressImageIOCoreTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import WICompress

@Suite("WICompress ImageIO Core", .tags(.imageIOCore, .compression))
struct WICompressImageIOCoreTests {
    struct JPEGBackgroundCase: CustomTestStringConvertible, Sendable {
        let background: WIJPEGBackground
        let testDescription: String
    }

    struct OrientationTransformCase: CustomTestStringConvertible, Sendable {
        let orientation: Int
        let displayWidth: Int
        let displayHeight: Int
        let testDescription: String
    }

    private struct PixelColor {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8

        func maxRGBDistance(to other: PixelColor) -> Int {
            max(
                abs(Int(red) - Int(other.red)),
                abs(Int(green) - Int(other.green)),
                abs(Int(blue) - Int(other.blue))
            )
        }
    }

    private static let jpegBackgroundCases: [JPEGBackgroundCase] = [
        JPEGBackgroundCase(background: .white, testDescription: "white background"),
        JPEGBackgroundCase(background: .black, testDescription: "black background"),
    ]

    private static let orientationTransformCases: [OrientationTransformCase] = [
        OrientationTransformCase(
            orientation: 1,
            displayWidth: 8,
            displayHeight: 4,
            testDescription: "orientation 1"
        ),
        OrientationTransformCase(
            orientation: 2,
            displayWidth: 8,
            displayHeight: 4,
            testDescription: "orientation 2"
        ),
        OrientationTransformCase(
            orientation: 3,
            displayWidth: 8,
            displayHeight: 4,
            testDescription: "orientation 3"
        ),
        OrientationTransformCase(
            orientation: 4,
            displayWidth: 8,
            displayHeight: 4,
            testDescription: "orientation 4"
        ),
        OrientationTransformCase(
            orientation: 5,
            displayWidth: 4,
            displayHeight: 8,
            testDescription: "orientation 5"
        ),
        OrientationTransformCase(
            orientation: 6,
            displayWidth: 4,
            displayHeight: 8,
            testDescription: "orientation 6"
        ),
        OrientationTransformCase(
            orientation: 7,
            displayWidth: 4,
            displayHeight: 8,
            testDescription: "orientation 7"
        ),
        OrientationTransformCase(
            orientation: 8,
            displayWidth: 4,
            displayHeight: 8,
            testDescription: "orientation 8"
        ),
    ]

    private struct ImageInfo {
        let width: Int
        let height: Int
        let orientation: Int
        let hasGPS: Bool
        let hasAlpha: Bool?
        let profileName: String?

        var displayWidth: Int {
            swapsDimensions ? height : width
        }

        var displayHeight: Int {
            swapsDimensions ? width : height
        }

        private var swapsDimensions: Bool {
            [5, 6, 7, 8].contains(orientation)
        }
    }

    private static func resource(_ name: String, extension ext: String) throws -> URL {
        try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Resources"
            ),
            "Missing fixture: \(name).\(ext)"
        )
    }

    private static func imageInfo(_ data: Data) throws -> ImageInfo {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try #require(properties.intValue(for: kCGImagePropertyPixelWidth))
        let height = try #require(properties.intValue(for: kCGImagePropertyPixelHeight))
        let orientation = properties.intValue(for: kCGImagePropertyOrientation) ?? 1

        return ImageInfo(
            width: width,
            height: height,
            orientation: orientation,
            hasGPS: properties.dictionaryExists(for: kCGImagePropertyGPSDictionary),
            hasAlpha: properties.boolValue(for: kCGImagePropertyHasAlpha),
            profileName: properties[kCGImagePropertyProfileName] as? String
        )
    }

    private static func decodedColorSpaceName(_ data: Data) throws -> String? {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return image.colorSpace?.name as String?
    }

    private static func pixelColor(_ data: Data, x: Int, y: Int) throws -> PixelColor {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
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
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                )
            )
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        let clampedX = min(max(x, 0), image.width - 1)
        let clampedY = min(max(y, 0), image.height - 1)
        let index = clampedY * bytesPerRow + clampedX * bytesPerPixel
        return PixelColor(
            red: pixels[index],
            green: pixels[index + 1],
            blue: pixels[index + 2],
            alpha: pixels[index + 3]
        )
    }

    @available(iOS 14.1, macOS 11.0, *)
    private static func hasGainMap(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }

        return CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source,
            0,
            kCGImageAuxiliaryDataTypeHDRGainMap
        ) != nil
    }

    private static func orientationTaggedJPEG(width: Int, height: Int, orientation: Int) throws -> Data {
        try solidImageData(
            typeIdentifier: "public.jpeg",
            width: width,
            height: height,
            properties: [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
    }

    private static func solidPNG(width: Int, height: Int) throws -> Data {
        try solidImageData(
            typeIdentifier: "public.png",
            width: width,
            height: height,
            properties: nil
        )
    }

    private static func transparentPNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        )

        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))

        return data as Data
    }

    private static func verticalBandsPNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        let bandWidth = CGFloat(width) / 4
        let colors = [
            CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            CGColor(red: 0, green: 0, blue: 1, alpha: 1),
            CGColor(red: 0, green: 1, blue: 0, alpha: 1),
            CGColor(red: 1, green: 1, blue: 0, alpha: 1),
        ]

        for (index, color) in colors.enumerated() {
            context.setFillColor(color)
            context.fill(
                CGRect(
                    x: CGFloat(index) * bandWidth,
                    y: 0,
                    width: bandWidth,
                    height: CGFloat(height)
                )
            )
        }

        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        )

        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))

        return data as Data
    }

    private static func expectColor(
        _ actual: PixelColor,
        matches expected: PixelColor,
        tolerance: Int = 48,
        _ message: String
    ) {
        #expect(actual.maxRGBDistance(to: expected) <= tolerance, Comment(rawValue: message))
    }

    private static func expectColor(
        _ actual: PixelColor,
        differsFrom expected: PixelColor,
        minimumDistance: Int = 96,
        _ message: String
    ) {
        #expect(actual.maxRGBDistance(to: expected) >= minimumDistance, Comment(rawValue: message))
    }

    private static func solidImageData(
        typeIdentifier: String,
        width: Int,
        height: Int,
        properties: CFDictionary?
    ) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, typeIdentifier as CFString, 1, nil)
        )

        CGImageDestinationAddImage(destination, image, properties)
        try #require(CGImageDestinationFinalize(destination))

        return data as Data
    }

    private static func quadrantJPEG(width: Int, height: Int, orientation: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
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
            CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)
        )

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        try #require(CGImageDestinationFinalize(destination))

        return data as Data
    }

    private static func orientationTransformedPNG(_ data: Data, maxPixelSize: Int) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let thumbnail = try #require(
            CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                ] as CFDictionary
            )
        )
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)
        )

        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImagePropertyOrientation: 1] as CFDictionary
        )
        try #require(CGImageDestinationFinalize(destination))

        return output as Data
    }

    private static func cmykJPEG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceCMYK()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        context.setFillColor([0, 1, 1, 0, 1])
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)
        )

        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))

        return data as Data
    }

    @Test("Default compression strips GPS, bakes orientation, and preserves display size contract")
    func defaultCompressionUsesRedrawBehavior() throws {
        let url = try Self.resource("real_heic_4032x3024_o6_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)

        let outputData = try WICompress.compress(inputData)
        let outputInfo = try Self.imageInfo(outputData)

        let ratio = WILuban.ratio(
            width: inputInfo.displayWidth,
            height: inputInfo.displayHeight
        )

        #expect(WIImageFormat(data: outputData) == WIImageFormat(data: inputData))
        #expect(outputInfo.hasGPS == false)
        #expect(outputInfo.orientation == 1)
        #expect(outputInfo.displayWidth == max(inputInfo.displayWidth / ratio, 1))
        #expect(outputInfo.displayHeight == max(inputInfo.displayHeight / ratio, 1))
        #expect(outputData.count < inputData.count)
    }

    @Test("Preserve metadata keeps GPS and orientation tag when copying from source")
    func preserveMetadataUsesCopyFromSourceBehavior() throws {
        let url = try Self.resource("real_heic_4032x3024_o6_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .luban,
                format: .preserve,
                metadata: .preserve,
                quality: .compression(0.6)
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        let ratio = WILuban.ratio(
            width: inputInfo.displayWidth,
            height: inputInfo.displayHeight
        )

        #expect(WIImageFormat(data: outputData) == WIImageFormat(data: inputData))
        #expect(outputInfo.hasGPS == true)
        #expect(outputInfo.orientation == inputInfo.orientation)
        #expect(outputInfo.displayWidth == max(inputInfo.displayWidth / ratio, 1))
        #expect(outputInfo.displayHeight == max(inputInfo.displayHeight / ratio, 1))
    }

    @Test("PNG alpha survives redraw compression")
    func pngAlphaSurvivesRedraw() throws {
        let url = try Self.resource("real_png_1086x1630_alpha", extension: "png")
        let inputData = try Data(contentsOf: url)

        let outputData = try WICompress.compress(inputData)
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .png)
        #expect(outputInfo.hasAlpha == true)
    }

    @Test("Transparent PNG can be flattened to JPEG with an explicit background", arguments: jpegBackgroundCases)
    func transparentPNGFlattensToJPEG(_ jpegBackgroundCase: JPEGBackgroundCase) throws {
        let url = try Self.resource("real_png_1086x1630_alpha", extension: "png")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.hasAlpha == true, "Fixture should contain alpha")

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .none,
                format: .jpeg(background: jpegBackgroundCase.background),
                metadata: .strip,
                quality: .compression(0.8)
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(outputInfo.hasAlpha != true)
        #expect(outputInfo.orientation == 1)
        #expect(outputInfo.displayWidth == inputInfo.displayWidth)
        #expect(outputInfo.displayHeight == inputInfo.displayHeight)
    }

    @Test("Transparent PNG to JPEG disallow throws")
    func transparentPNGToJPEGDisallowThrows() throws {
        let url = try Self.resource("real_png_1086x1630_alpha", extension: "png")
        let inputData = try Data(contentsOf: url)

        #expect(throws: WICompressError.transparentSourceRequiresBackground(.png)) {
            _ = try WICompress.compress(
                inputData,
                options: WICompressOptions(
                    resize: .none,
                    format: .jpeg(background: .disallow),
                    metadata: .strip,
                    quality: .compression(0.8)
                )
            )
        }
    }

    @Test("Alpha-aware format keeps transparent sources as PNG")
    func alphaAwareFormatKeepsTransparentSourcesAsPNG() throws {
        let url = try Self.resource("real_png_1086x1630_alpha", extension: "png")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.hasAlpha == true, "Fixture should contain alpha")

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .none,
                format: .pngIfAlphaOtherwiseJPEG,
                metadata: .strip,
                quality: .compression(0.8)
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .png)
        #expect(outputInfo.hasAlpha == true)
        #expect(outputInfo.displayWidth == inputInfo.displayWidth)
        #expect(outputInfo.displayHeight == inputInfo.displayHeight)
    }

    @Test("Alpha-aware format converts opaque sources to JPEG")
    func alphaAwareFormatConvertsOpaqueSourcesToJPEG() throws {
        let url = try Self.resource("real_jpeg_2098x1350_landscape", extension: "jpg")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.hasAlpha != true, "Fixture should be opaque")

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .none,
                format: .pngIfAlphaOtherwiseJPEG,
                metadata: .strip,
                quality: .compression(0.8)
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(outputInfo.hasAlpha != true)
        #expect(outputInfo.displayWidth == inputInfo.displayWidth)
        #expect(outputInfo.displayHeight == inputInfo.displayHeight)
    }

    @Test("Explicit PNG conversion follows maxPixel cap")
    func explicitPNGConversionFollowsMaxPixelCap() throws {
        let url = try Self.resource("real_jpeg_2098x1350_landscape", extension: "jpg")
        let inputData = try Data(contentsOf: url)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .maxPixel(600),
                format: .png,
                metadata: .strip,
                quality: .compression(0.1)
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .png)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) <= 600)
    }

    @Test(".fit resize upscales small assets")
    func fitResizeUpscalesSmallAssets() throws {
        let inputData = try Self.solidPNG(width: 20, height: 20)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .fit(
                    minSize: WISize(width: 40, height: 50),
                    maxSize: WISize(width: 400, height: 467)
                ),
                format: .preserve,
                metadata: .strip,
                quality: .none
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .png)
        #expect(outputInfo.displayWidth == 40)
        #expect(outputInfo.displayHeight == 40)
    }

    @Test(".fit resize downscales large assets")
    func fitResizeDownscalesLargeAssets() throws {
        let inputData = try Self.solidPNG(width: 720, height: 1080)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .fit(
                    minSize: WISize(width: 40, height: 50),
                    maxSize: WISize(width: 400, height: 467)
                ),
                format: .preserve,
                metadata: .strip,
                quality: .none
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .png)
        #expect(outputInfo.displayWidth == 311)
        #expect(outputInfo.displayHeight == 467)
    }

    @Test(".fit resize downscales assets with only one oversized side")
    func fitResizeDownscalesSingleOversizedSide() throws {
        let inputData = try Self.solidPNG(width: 1200, height: 100)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .fit(
                    minSize: WISize(width: 40, height: 50),
                    maxSize: WISize(width: 400, height: 467)
                ),
                format: .preserve,
                metadata: .strip,
                quality: .none
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .png)
        #expect(outputInfo.displayWidth == 400)
        #expect(outputInfo.displayHeight == 33)
    }

    @Test("Explicit same-format JPEG still rewrites instead of returning original")
    func explicitSameFormatJPEGDoesNotReturnOriginal() throws {
        let url = try Self.resource("real_jpeg_738x1302_recompressed", extension: "jpg")
        let inputData = try Data(contentsOf: url)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .none,
                format: .jpeg(background: .disallow),
                metadata: .preserve,
                quality: .compression(0.6)
            )
        )

        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(outputData != inputData)
    }

    @Test("Metadata preserve keeps GPS while converting format")
    func metadataPreserveKeepsGPSDuringFormatConversion() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.hasGPS == true, "Fixture should contain GPS metadata")

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .maxPixel(1200),
                format: .jpeg(background: .disallow),
                metadata: .preserve,
                quality: .compression(0.7)
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(outputInfo.hasGPS == true)
        #expect(outputInfo.orientation == 1)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) <= 1200)
    }

    @Test("Display P3 profile survives copyFromSource")
    func displayP3ProfileSurvivesCopyFromSource() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.profileName == "Display P3", "Fixture should be Display P3")

        let options = WICompressOptions(
            resize: .luban,
            format: .preserve,
            metadata: .preserve,
            quality: .compression(0.6)
        )
        let inputSource = try WIImageSource(data: inputData)
        let writePlan = try WIWritePlanResolver.resolve(options: options, info: inputSource.info)

        let outputData = try WICompress.compress(inputData, options: options)
        let outputInfo = try Self.imageInfo(outputData)

        #expect(writePlan.path == .copyFromSource)
        #expect(outputInfo.profileName == inputInfo.profileName)
    }

    @Test("Display P3 profile survives redrawBitmap")
    func displayP3ProfileSurvivesRedrawBitmap() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.profileName == "Display P3", "Fixture should be Display P3")

        let options = WICompressOptions(
            resize: .luban,
            format: .preserve,
            metadata: .strip,
            quality: .compression(0.6)
        )
        let inputSource = try WIImageSource(data: inputData)
        let writePlan = try WIWritePlanResolver.resolve(options: options, info: inputSource.info)

        let outputData = try WICompress.compress(inputData, options: options)
        let outputInfo = try Self.imageInfo(outputData)

        #expect(writePlan.path == .redrawBitmap)
        #expect(outputInfo.profileName == inputInfo.profileName)
    }

    @Test("Color-space inspection is lazy for preserve and resolves Display P3 when requested")
    func colorSpaceInspectionIsLazyForPreserve() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputSource = try WIImageSource(data: inputData)

        #expect(try inputSource.colorSpaceInfoIfNeeded(for: .preserve) == nil)

        let colorSpaceInfo = try #require(
            try inputSource.colorSpaceInfoIfNeeded(for: .convert(to: .sRGB))
        )
        #expect(colorSpaceInfo.colorSpace == .displayP3)
    }

    @Test("Display P3 can be converted to sRGB")
    func displayP3ConvertsToSRGB() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        try #require(Self.decodedColorSpaceName(inputData) == CGColorSpace.displayP3 as String)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .none,
                format: .preserve,
                metadata: .strip,
                quality: .compression(0.8),
                colorSpace: .convert(to: .sRGB)
            )
        )
        let outputColorSpaceName = try Self.decodedColorSpaceName(outputData)

        #expect(WIImageFormat(data: outputData) == WIImageFormat(data: inputData))
        #expect(outputColorSpaceName == CGColorSpace.sRGB as String)
    }

    @Test("Target fill geometry renders a fixed canvas")
    func targetFillGeometryRendersFixedCanvas() throws {
        let url = try Self.resource("real_jpeg_2098x1350_landscape", extension: "jpg")
        let inputData = try Data(contentsOf: url)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 1_000_000,
                geometry: .fill(size: WISize(width: 320, height: 320)),
                output: WICompressionOutput(format: .jpeg(background: .disallow))
            )
        )
        let outputInfo = try Self.imageInfo(result.data)

        #expect(result.format == .jpeg)
        #expect(result.pixelSize == WISize(width: 320, height: 320))
        #expect(outputInfo.orientation == 1)
        #expect(outputInfo.displayWidth == 320)
        #expect(outputInfo.displayHeight == 320)
    }

    @Test("Lossy target searches quality for fixed canvas geometry")
    func lossyTargetSearchesQualityForFixedCanvasGeometry() throws {
        let url = try Self.resource("real_jpeg_2098x1350_landscape", extension: "jpg")
        let inputData = try Data(contentsOf: url)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 12_000,
                geometry: .fill(size: WISize(width: 320, height: 320)),
                output: WICompressionOutput(format: .jpeg(background: .disallow))
            )
        )
        let outputInfo = try Self.imageInfo(result.data)

        #expect(result.format == .jpeg)
        #expect(result.byteCount <= 12_000)
        #expect(result.pixelSize == WISize(width: 320, height: 320))
        #expect(outputInfo.displayWidth == 320)
        #expect(outputInfo.displayHeight == 320)
    }

    @Test("Lossy target fails when fixed geometry cannot meet byte limit")
    func lossyTargetFailsWhenFixedGeometryCannotMeetByteLimit() throws {
        let url = try Self.resource("real_jpeg_2098x1350_landscape", extension: "jpg")
        let inputData = try Data(contentsOf: url)
        let target = WICompressionTarget(
            maxBytes: 1,
            geometry: .fill(size: WISize(width: 320, height: 320)),
            output: WICompressionOutput(format: .jpeg(background: .disallow))
        )

        do {
            _ = try WICompress.compress(inputData, to: target)
            Issue.record("Expected targetUnsatisfiable")
        } catch WICompressError.targetUnsatisfiable(let smallestByteCount) {
            #expect((smallestByteCount ?? 0) > target.maxBytes)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Lossy target lowers soft geometry dimensions when quality is not enough")
    func lossyTargetLowersSoftGeometryDimensions() throws {
        let url = try Self.resource("real_jpeg_2098x1350_landscape", extension: "jpg")
        let inputData = try Data(contentsOf: url)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 10_000,
                geometry: .fit(maxLongSide: 1200),
                output: WICompressionOutput(format: .jpeg(background: .disallow))
            )
        )
        let outputInfo = try Self.imageInfo(result.data)

        #expect(result.format == .jpeg)
        #expect(result.byteCount <= 10_000)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) < 1200)
        #expect(result.pixelSize == WISize(
            width: Double(outputInfo.displayWidth),
            height: Double(outputInfo.displayHeight)
        ))
    }

    @Test("Lossy target returns existing candidate when attempt budget cannot cover another size")
    func lossyTargetReturnsExistingCandidateWhenAttemptBudgetCannotCoverAnotherSize() throws {
        let url = try Self.resource("real_jpeg_2098x1350_landscape", extension: "jpg")
        let inputData = try Data(contentsOf: url)
        let imageSource = try WIImageSource(data: inputData)
        let target = WICompressionTarget(
            maxBytes: 60_000,
            geometry: .fit(maxLongSide: 1200),
            output: WICompressionOutput(format: .jpeg(background: .disallow))
        )

        let outputData = try WICompressionSolver.compress(
            imageSource,
            to: target,
            sourceColorSpace: nil,
            maxEncodeAttempts: 12
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(outputData.count <= target.maxBytes)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) == 1200)
    }

    @Test("Target candidate ranking applies compression preference")
    func targetCandidateRankingAppliesCompressionPreference() {
        let largeLowQuality = WISolvedCompressionCandidate(
            data: Data(count: 80),
            pixelSize: WIPixelSize(width: 1_000, height: 1_000),
            format: .jpeg,
            quality: 0.45
        )
        let smallerHighQuality = WISolvedCompressionCandidate(
            data: Data(count: 70),
            pixelSize: WIPixelSize(width: 800, height: 800),
            format: .jpeg,
            quality: 0.72
        )
        let referencePixelSize = WIPixelSize(width: 1_000, height: 1_000)
        let candidates = [largeLowQuality, smallerHighQuality]

        let resolutionCandidate = WICompressionSolver.bestCandidate(
            candidates,
            preference: .preserveResolution,
            referencePixelSize: referencePixelSize
        )
        let fidelityCandidate = WICompressionSolver.bestCandidate(
            candidates,
            preference: .preserveFidelity,
            referencePixelSize: referencePixelSize
        )

        #expect(resolutionCandidate == largeLowQuality)
        #expect(fidelityCandidate == smallerHighQuality)
    }

    @Test("Target fill left crop keeps left source content")
    func targetFillLeftCropKeepsLeftSourceContent() throws {
        let inputData = try Self.quadrantJPEG(width: 8, height: 4, orientation: 1)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                geometry: .fill(size: WISize(width: 4, height: 4), crop: .left),
                output: WICompressionOutput(format: .png)
            )
        )
        let samplePoints = [
            (x: 0, y: 0),
            (x: 3, y: 0),
            (x: 0, y: 3),
            (x: 3, y: 3),
        ]

        for point in samplePoints {
            let actual = try Self.pixelColor(result.data, x: point.x, y: point.y)
            let expected = try Self.pixelColor(inputData, x: point.x, y: point.y)
            Self.expectColor(
                actual,
                matches: expected,
                "left crop point \(point) should match source left half"
            )
        }

        let rightEdge = try Self.pixelColor(inputData, x: 7, y: 0)
        let outputRightEdge = try Self.pixelColor(result.data, x: 3, y: 0)
        Self.expectColor(
            outputRightEdge,
            differsFrom: rightEdge,
            "left crop should remove the source right edge"
        )
    }

    @Test("Target exactCanvas fill top crop keeps top source content")
    func targetExactCanvasFillTopCropKeepsTopSourceContent() throws {
        let inputData = try Self.quadrantJPEG(width: 4, height: 8, orientation: 1)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                geometry: .exactCanvas(
                    size: WISize(width: 4, height: 4),
                    placement: .fill(.top),
                    background: WIColor(red: 0, green: 0, blue: 0)
                ),
                output: WICompressionOutput(format: .png)
            )
        )
        let samplePairs = [
            (actual: (x: 0, y: 0), expected: (x: 0, y: 0)),
            (actual: (x: 3, y: 0), expected: (x: 3, y: 0)),
            (actual: (x: 0, y: 3), expected: (x: 0, y: 3)),
            (actual: (x: 3, y: 3), expected: (x: 3, y: 3)),
        ]

        for pair in samplePairs {
            let actual = try Self.pixelColor(result.data, x: pair.actual.x, y: pair.actual.y)
            let expected = try Self.pixelColor(inputData, x: pair.expected.x, y: pair.expected.y)
            Self.expectColor(
                actual,
                matches: expected,
                "top crop point \(pair.actual) should match source point \(pair.expected)"
            )
        }

        let sourceBottomEdge = try Self.pixelColor(inputData, x: 0, y: 7)
        let outputBottomEdge = try Self.pixelColor(result.data, x: 0, y: 3)
        Self.expectColor(
            outputBottomEdge,
            differsFrom: sourceBottomEdge,
            "top crop should remove the source bottom edge"
        )
    }

    @Test("Target exactCanvas fill center crop drops horizontal edges")
    func targetExactCanvasFillCenterCropDropsHorizontalEdges() throws {
        let inputData = try Self.verticalBandsPNG(width: 8, height: 4)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                geometry: .exactCanvas(
                    size: WISize(width: 4, height: 4),
                    placement: .fill(.center),
                    background: WIColor(red: 0, green: 0, blue: 0)
                ),
                output: WICompressionOutput(format: .png)
            )
        )
        let samplePairs = [
            (actual: (x: 0, y: 0), expected: (x: 2, y: 0)),
            (actual: (x: 3, y: 0), expected: (x: 5, y: 0)),
            (actual: (x: 0, y: 3), expected: (x: 2, y: 3)),
            (actual: (x: 3, y: 3), expected: (x: 5, y: 3)),
        ]

        for pair in samplePairs {
            let actual = try Self.pixelColor(result.data, x: pair.actual.x, y: pair.actual.y)
            let expected = try Self.pixelColor(inputData, x: pair.expected.x, y: pair.expected.y)
            Self.expectColor(
                actual,
                matches: expected,
                tolerance: 8,
                "center crop point \(pair.actual) should match source point \(pair.expected)"
            )
        }

        let leftEdge = try Self.pixelColor(inputData, x: 0, y: 0)
        let rightEdge = try Self.pixelColor(inputData, x: 7, y: 0)
        Self.expectColor(
            try Self.pixelColor(result.data, x: 0, y: 0),
            differsFrom: leftEdge,
            "center crop should remove the left edge"
        )
        Self.expectColor(
            try Self.pixelColor(result.data, x: 3, y: 0),
            differsFrom: rightEdge,
            "center crop should remove the right edge"
        )
    }

    @Test("Target exactCanvas fit renders background padding")
    func targetExactCanvasFitRendersBackgroundPadding() throws {
        let inputData = try Self.solidPNG(width: 20, height: 10)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                geometry: .exactCanvas(
                    size: WISize(width: 20, height: 20),
                    placement: .fit(.center),
                    background: WIColor(red: 0, green: 1, blue: 0)
                ),
                output: WICompressionOutput(format: .png)
            )
        )
        let outputInfo = try Self.imageInfo(result.data)
        let corner = try Self.pixelColor(result.data, x: 0, y: 0)

        #expect(result.format == .png)
        #expect(outputInfo.displayWidth == 20)
        #expect(outputInfo.displayHeight == 20)
        #expect(corner.red < 40)
        #expect(corner.green > 200)
        #expect(corner.blue < 40)
        #expect(corner.alpha > 240)
    }

    @Test("Target exactCanvas uses JPEG background only inside source alpha")
    func targetExactCanvasUsesJPEGBackgroundInsideSourceAlpha() throws {
        let inputData = try Self.transparentPNG(width: 20, height: 10)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                geometry: .exactCanvas(
                    size: WISize(width: 20, height: 20),
                    placement: .fit(.center),
                    background: WIColor(red: 0, green: 1, blue: 0)
                ),
                output: WICompressionOutput(format: .jpeg(background: .white))
            )
        )
        let padding = try Self.pixelColor(result.data, x: 0, y: 0)
        let sourceArea = try Self.pixelColor(result.data, x: 10, y: 10)

        #expect(result.format == .jpeg)
        #expect(padding.red < 80)
        #expect(padding.green > 160)
        #expect(padding.blue < 80)
        #expect(sourceArea.red > 180)
        #expect(sourceArea.green > 180)
        #expect(sourceArea.blue > 180)
    }

    @Test("Target canvas preserve metadata still resets baked orientation")
    func targetCanvasPreserveMetadataResetsOrientation() throws {
        let url = try Self.resource("real_heic_4032x3024_o6_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.orientation == 6)
        try #require(inputInfo.hasGPS == true)

        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 1_000_000,
                geometry: .fill(size: WISize(width: 200, height: 200)),
                output: .preserve
            )
        )
        let outputInfo = try Self.imageInfo(result.data)

        #expect(result.format == .heif)
        #expect(result.pixelSize == WISize(width: 200, height: 200))
        #expect(outputInfo.hasGPS == true)
        #expect(outputInfo.orientation == 1)
        #expect(outputInfo.displayWidth == 200)
        #expect(outputInfo.displayHeight == 200)
    }

    @Test("Target canvas orientation transform matches ImageIO display transform", arguments: orientationTransformCases)
    func targetCanvasOrientationTransformMatchesImageIO(_ orientationCase: OrientationTransformCase) throws {
        let inputData = try Self.quadrantJPEG(width: 8, height: 4, orientation: orientationCase.orientation)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                geometry: .exactCanvas(
                    size: WISize(
                        width: Double(orientationCase.displayWidth),
                        height: Double(orientationCase.displayHeight)
                    ),
                    placement: .stretch,
                    background: WIColor(red: 0, green: 0, blue: 0)
                ),
                output: WICompressionOutput(format: .png)
            )
        )
        let oracle = try Self.orientationTransformedPNG(
            inputData,
            maxPixelSize: max(orientationCase.displayWidth, orientationCase.displayHeight)
        )
        let samplePoints = [
            (x: 0, y: 0),
            (x: orientationCase.displayWidth - 1, y: 0),
            (x: 0, y: orientationCase.displayHeight - 1),
            (x: orientationCase.displayWidth - 1, y: orientationCase.displayHeight - 1),
        ]

        for point in samplePoints {
            let actual = try Self.pixelColor(result.data, x: point.x, y: point.y)
            let expected = try Self.pixelColor(oracle, x: point.x, y: point.y)
            let message = """
            point: \(point), actual: \(actual.red),\(actual.green),\(actual.blue), \
            expected: \(expected.red),\(expected.green),\(expected.blue)
            """
            #expect(abs(Int(actual.red) - Int(expected.red)) < 48, Comment(rawValue: message))
            #expect(abs(Int(actual.green) - Int(expected.green)) < 48, Comment(rawValue: message))
            #expect(abs(Int(actual.blue) - Int(expected.blue)) < 48, Comment(rawValue: message))
        }
    }

    @Test("Transparent PNG can be flattened to JPEG with a custom background")
    func transparentPNGFlattensToJPEGWithCustomBackground() throws {
        let url = try Self.resource("real_png_1086x1630_alpha", extension: "png")
        let inputData = try Data(contentsOf: url)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .none,
                format: .jpeg(
                    background: .color(
                        WIColor(red: 0.9, green: 0.1, blue: 0.1, colorSpace: .displayP3)
                    )
                ),
                metadata: .strip,
                quality: .compression(0.8),
                colorSpace: .convert(to: .sRGB)
            )
        )
        let outputInfo = try Self.imageInfo(outputData)
        let outputColorSpaceName = try Self.decodedColorSpaceName(outputData)

        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(outputInfo.hasAlpha != true)
        #expect(outputColorSpaceName == CGColorSpace.sRGB as String)
    }

    @Test("CMYK JPEG preserve still compresses without throwing")
    func cmykJPEGWithPreserveStillCompresses() throws {
        let inputData = try Self.cmykJPEG(width: 320, height: 240)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .maxPixel(160),
                format: .preserve,
                metadata: .strip,
                quality: .compression(0.8),
                colorSpace: .preserve
            )
        )

        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(!outputData.isEmpty)
    }

    @Test("Size guard may return original when preserve policies are already satisfied")
    func sizeGuardReturnsOriginalForPreservePolicies() throws {
        let inputData = try Self.solidPNG(width: 1, height: 1)
        let inputSource = try WIImageSource(data: inputData)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .luban,
                format: .preserve,
                metadata: .preserve,
                quality: .compression(0.6)
            )
        )

        #expect(inputSource.info.orientation == 1)
        #expect(outputData == inputData)
    }

    @Test("Size guard does not bypass orientation normalization for stripped metadata")
    func sizeGuardDoesNotBypassOrientationNormalization() throws {
        let inputData = try Self.orientationTaggedJPEG(width: 2, height: 4, orientation: 6)
        let inputInfo = try Self.imageInfo(inputData)

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .none,
                format: .preserve,
                metadata: .strip,
                quality: .none
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(inputInfo.orientation == 6)
        #expect(inputInfo.hasGPS == false)
        #expect(outputInfo.orientation == 1)
        #expect(outputInfo.displayWidth == inputInfo.displayWidth)
        #expect(outputInfo.displayHeight == inputInfo.displayHeight)
    }

    // v1 documented behavior: `.preserve` keeps Exif/GPS/orientation but NOT the
    // HDR gain map (the encoder does not set kCGImageDestinationPreserveGainMap).
    // This locks the current trade-off; it will flip intentionally when gain-map
    // preservation lands (see PLAN §8.3 / §17).
    @available(iOS 14.1, macOS 11.0, *)
    @Test("Preserve metadata drops the HDR gain map in v1")
    func preserveMetadataDropsGainMap() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)

        try #require(Self.hasGainMap(inputData), "Fixture should contain an HDR gain map")

        let outputData = try WICompress.compress(
            inputData,
            options: WICompressOptions(
                resize: .luban,
                format: .preserve,
                metadata: .preserve,
                quality: .compression(0.6)
            )
        )

        #expect(Self.hasGainMap(outputData) == false)
    }

    @Test("Animated images are rejected")
    func animatedImageThrows() throws {
        let url = try Self.resource("real_gif_555x555_4frames", extension: "gif")
        let inputData = try Data(contentsOf: url)

        #expect(throws: WICompressError.animatedSourceUnsupported(frameCount: 4)) {
            _ = try WICompress.compress(inputData)
        }
    }
}
