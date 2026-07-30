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

    @Test("Default Process strips GPS, bakes orientation, and preserves display size contract")
    func defaultProcessUsesRenderBehavior() throws {
        let url = try Self.resource("real_heic_4032x3024_o6_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)

        let outputData = try WICompress.process(inputData)
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

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .original,
                quality: 0.6,
                output: WIImageOutput(
                    representation: .preserve,
                    metadata: .preserve,
                    colorSpace: .preserve
                )
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == WIImageFormat(data: inputData))
        #expect(outputInfo.hasGPS == true)
        #expect(outputInfo.orientation == inputInfo.orientation)
        #expect(outputInfo.displayWidth == inputInfo.displayWidth)
        #expect(outputInfo.displayHeight == inputInfo.displayHeight)
    }

    @Test("PNG alpha survives redraw compression")
    func pngAlphaSurvivesRedraw() throws {
        let url = try Self.resource("real_png_1086x1630_alpha", extension: "png")
        let inputData = try Data(contentsOf: url)

        let outputData = try WICompress.process(inputData)
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

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .original,
                quality: 0.8,
                output: WIImageOutput(
                    representation: .jpeg(
                        background: jpegBackgroundCase.background
                    ),
                    metadata: .strip,
                    colorSpace: .preserve
                )
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
            _ = try WICompress.process(
                inputData,
                using: WIImageProcess(
                    sizing: .original,
                    quality: 0.8,
                    output: WIImageOutput(
                        representation: .jpeg(),
                        metadata: .strip,
                        colorSpace: .preserve
                    )
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

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .original,
                quality: 0.8,
                output: WIImageOutput(
                    representation: .pngIfAlphaOtherwiseJPEG,
                    metadata: .strip,
                    colorSpace: .preserve
                )
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

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .original,
                quality: 0.8,
                output: WIImageOutput(
                    representation: .pngIfAlphaOtherwiseJPEG,
                    metadata: .strip,
                    colorSpace: .preserve
                )
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

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .resize(
                    using: WIImageResize.maximumPixelSize(600)
                ),
                quality: 0.1,
                output: WIImageOutput(
                    representation: .png,
                    metadata: .strip,
                    colorSpace: .preserve
                )
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(WIImageFormat(data: outputData) == .png)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) <= 600)
    }

    @Test("Explicit same-format JPEG still rewrites instead of returning original")
    func explicitSameFormatJPEGDoesNotReturnOriginal() throws {
        let url = try Self.resource("real_jpeg_738x1302_recompressed", extension: "jpg")
        let inputData = try Data(contentsOf: url)

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .original,
                quality: 0.6,
                output: WIImageOutput(
                    representation: .jpeg(),
                    metadata: .preserve,
                    colorSpace: .preserve
                )
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

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .resize(
                    using: WIImageResize.maximumPixelSize(1200)
                ),
                quality: 0.7,
                output: WIImageOutput(
                    representation: .jpeg(),
                    metadata: .preserve,
                    colorSpace: .preserve
                )
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

        let process = WIImageProcess(
            sizing: .original,
            quality: 0.6,
            output: WIImageOutput(
                representation: .preserve,
                metadata: .preserve,
                colorSpace: .preserve
            )
        )
        let inputSource = try WIImageSource(data: inputData)
        let executionPlan = try WIImageProcessResolver.resolve(
            process,
            imageSource: inputSource
        )

        let outputData = try WICompress.process(inputData, using: process)
        let outputInfo = try Self.imageInfo(outputData)

        #expect(executionPlan.operation == .copyFromSource)
        #expect(outputInfo.profileName == inputInfo.profileName)
    }

    @Test("Display P3 profile survives redrawBitmap")
    func displayP3ProfileSurvivesRedrawBitmap() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.profileName == "Display P3", "Fixture should be Display P3")

        let process = WIImageProcess(
            sizing: .resize(using: WIImageResize.luban),
            quality: 0.6,
            output: WIImageOutput(
                representation: .preserve,
                metadata: .strip,
                colorSpace: .preserve
            )
        )
        let inputSource = try WIImageSource(data: inputData)
        let executionPlan = try WIImageProcessResolver.resolve(
            process,
            imageSource: inputSource
        )

        let outputData = try WICompress.process(inputData, using: process)
        let outputInfo = try Self.imageInfo(outputData)

        guard case .render = executionPlan.operation else {
            Issue.record("Expected render execution")
            return
        }
        #expect(outputInfo.profileName == inputInfo.profileName)
    }

    @Test("Color-space inspection is lazy for preserve and resolves Display P3 when requested")
    func colorSpaceInspectionIsLazyForPreserve() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputSource = try WIImageSource(data: inputData)

        #expect(
            try inputSource.processColorSpaceInfoIfNeeded(
                for: .preserve
            ) == nil
        )

        let colorSpaceInfo = try #require(
            try inputSource.processColorSpaceInfoIfNeeded(
                for: .convert(to: .sRGB)
            )
        )
        #expect(colorSpaceInfo.colorSpace == .displayP3)
    }

    @Test("Display P3 can be converted to sRGB")
    func displayP3ConvertsToSRGB() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        try #require(Self.decodedColorSpaceName(inputData) == CGColorSpace.displayP3 as String)

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .original,
                quality: 0.8,
                output: WIImageOutput(
                    representation: .preserve,
                    metadata: .strip,
                    colorSpace: .convert(to: .sRGB)
                )
            )
        )
        let outputColorSpaceName = try Self.decodedColorSpaceName(outputData)

        #expect(WIImageFormat(data: outputData) == WIImageFormat(data: inputData))
        #expect(outputColorSpaceName == CGColorSpace.sRGB as String)
    }

    @Test("Default Target output converts Display P3 to sRGB")
    func defaultTargetOutputConvertsDisplayP3ToSRGB() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        try #require(Self.decodedColorSpaceName(inputData) == CGColorSpace.displayP3 as String)

        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(maxBytes: inputData.count * 2)
        )

        #expect(result.format == .jpeg)
        #expect(result.byteCount <= inputData.count * 2)
        #expect(try Self.decodedColorSpaceName(result.data) == CGColorSpace.sRGB as String)
    }

    @Test("Default Target output keeps Alpha sources as PNG")
    func defaultTargetOutputKeepsAlphaAsPNG() throws {
        let inputData = try Self.transparentPNG(width: 32, height: 24)

        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(maxBytes: 1_000_000)
        )
        let outputInfo = try Self.imageInfo(result.data)

        #expect(result.format == .png)
        #expect(outputInfo.hasAlpha == true)
    }

    @Test("Lossy target lowers dimensions when quality is not enough")
    func lossyTargetLowersDimensions() throws {
        let url = try Self.resource("real_jpeg_2098x1350_landscape", extension: "jpg")
        let inputData = try Data(contentsOf: url)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 10_000,
                sizing: WICompressionSizing(maximumPixelSize: 1200),
                output: WIImageOutput(representation: .jpeg(background: .disallow))
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

    @Test("Target solver keeps the fixed aspect ratio while shrinking")
    func targetSolverKeepsFixedAspectRatio() throws {
        let url = try Self.resource(
            "real_jpeg_2098x1350_landscape",
            extension: "jpg"
        )
        let inputData = try Data(contentsOf: url)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 10_000,
                sizing: WICompressionSizing(
                    maximumPixelSize: 1200,
                    aspectRatio: WIAspectRatio(width: 1, height: 1)
                ),
                output: WIImageOutput(
                    representation: .jpeg(background: .disallow)
                )
            )
        )
        let outputInfo = try Self.imageInfo(result.data)

        #expect(result.byteCount <= 10_000)
        #expect(outputInfo.displayWidth == outputInfo.displayHeight)
        #expect(outputInfo.displayWidth < 1200)
    }

    @Test("Lossy target returns existing candidate when attempt budget cannot cover another size")
    func lossyTargetReturnsExistingCandidateWhenAttemptBudgetCannotCoverAnotherSize() throws {
        let url = try Self.resource("real_jpeg_2098x1350_landscape", extension: "jpg")
        let inputData = try Data(contentsOf: url)
        let imageSource = try WIImageSource(data: inputData)
        let target = WICompressionTarget(
            maxBytes: 60_000,
            sizing: WICompressionSizing(maximumPixelSize: 1200),
            output: WIImageOutput(representation: .jpeg(background: .disallow))
        )

        let outputData = try WICompressionSolver.compress(
            imageSource,
            to: target,
            maxEncodeAttempts: 12
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(outputData.count <= target.maxBytes)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) == 1200)
    }

    @Test("PNG target lowers dimensions")
    func pngTargetLowersDimensions() throws {
        let url = try Self.resource("real_png_1928x464_pano", extension: "png")
        let inputData = try Data(contentsOf: url)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                sizing: WICompressionSizing(maximumPixelSize: 1200),
                output: WIImageOutput(representation: .png)
            )
        )
        let outputInfo = try Self.imageInfo(result.data)

        #expect(result.format == .png)
        #expect(result.byteCount <= 100_000)
        #expect(max(outputInfo.displayWidth, outputInfo.displayHeight) < 1200)
        #expect(result.pixelSize == WISize(
            width: Double(outputInfo.displayWidth),
            height: Double(outputInfo.displayHeight)
        ))
    }

    @Test("PNG target fails when even one pixel cannot meet the byte limit")
    func pngTargetFailsAtMinimumPixelSize() throws {
        let url = try Self.resource("real_png_814x386_wide", extension: "png")
        let inputData = try Data(contentsOf: url)
        let target = WICompressionTarget(
            maxBytes: 1,
            output: WIImageOutput(representation: .png)
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

    @Test("Target candidate ranking uses one deterministic balance")
    func targetCandidateRankingIsDeterministic() {
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

        let candidate = WICompressionRanking.bestCandidate(
            candidates,
            referencePixelSize: referencePixelSize
        )

        #expect(candidate == smallerHighQuality)
    }

    @Test("Target aspect-ratio crop honors its normalized anchor")
    func targetAspectRatioCropHonorsAnchor() throws {
        let inputData = try Self.quadrantJPEG(width: 8, height: 4, orientation: 1)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                sizing: WICompressionSizing(
                    aspectRatio: WIAspectRatio(width: 1, height: 1),
                    anchor: WICropAnchor(x: 0, y: 0.5)
                ),
                output: WIImageOutput(representation: .png)
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

    @Test("Target top anchor keeps the top of a tall source")
    func targetTopAnchorKeepsTopSourceContent() throws {
        let inputData = try Self.quadrantJPEG(width: 4, height: 8, orientation: 1)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                sizing: WICompressionSizing(
                    aspectRatio: WIAspectRatio(width: 1, height: 1),
                    anchor: WICropAnchor(x: 0.5, y: 0)
                ),
                output: WIImageOutput(representation: .png)
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

    @Test("Target centered aspect-ratio crop drops both horizontal edges")
    func targetCenteredAspectRatioCropDropsHorizontalEdges() throws {
        let inputData = try Self.verticalBandsPNG(width: 8, height: 4)
        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 100_000,
                sizing: WICompressionSizing(
                    aspectRatio: WIAspectRatio(width: 1, height: 1)
                ),
                output: WIImageOutput(representation: .png)
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

    @Test("Target crop preserves metadata while baking orientation")
    func targetCropPreservesMetadataAndBakesOrientation() throws {
        let url = try Self.resource("real_heic_4032x3024_o6_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)
        let inputInfo = try Self.imageInfo(inputData)
        try #require(inputInfo.orientation == 6)
        try #require(inputInfo.hasGPS == true)

        let result = try WICompress.compress(
            inputData,
            to: WICompressionTarget(
                maxBytes: 1_000_000,
                sizing: WICompressionSizing(
                    maximumPixelSize: 200,
                    aspectRatio: WIAspectRatio(width: 1, height: 1)
                ),
                output: WIImageOutput(
                    representation: .preserve,
                    metadata: .preserve,
                    colorSpace: .preserve
                )
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

    @Test("Transparent PNG can be flattened to JPEG with a custom background")
    func transparentPNGFlattensToJPEGWithCustomBackground() throws {
        let url = try Self.resource("real_png_1086x1630_alpha", extension: "png")
        let inputData = try Data(contentsOf: url)

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .original,
                quality: 0.8,
                output: WIImageOutput(
                    representation: .jpeg(
                        background: .color(
                        WIColor(red: 0.9, green: 0.1, blue: 0.1, colorSpace: .displayP3)
                        )
                    ),
                    metadata: .strip,
                    colorSpace: .convert(to: .sRGB)
                )
            )
        )
        let outputInfo = try Self.imageInfo(outputData)
        let outputColorSpaceName = try Self.decodedColorSpaceName(outputData)

        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(outputInfo.hasAlpha != true)
        #expect(outputColorSpaceName == CGColorSpace.sRGB as String)
    }

    @Test("CMYK JPEG preserve still processes without throwing")
    func cmykJPEGWithPreserveStillProcesses() throws {
        let inputData = try Self.cmykJPEG(width: 320, height: 240)

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .resize(
                    using: WIImageResize.maximumPixelSize(160)
                ),
                quality: 0.8,
                output: WIImageOutput(
                    representation: .preserve,
                    metadata: .strip,
                    colorSpace: .preserve
                )
            )
        )

        #expect(WIImageFormat(data: outputData) == .jpeg)
        #expect(!outputData.isEmpty)
    }

    @Test("Process normalizes orientation when stripping metadata")
    func processNormalizesOrientationWhenStrippingMetadata() throws {
        let inputData = try Self.orientationTaggedJPEG(width: 2, height: 4, orientation: 6)
        let inputInfo = try Self.imageInfo(inputData)

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .original,
                quality: nil,
                output: WIImageOutput(
                    representation: .preserve,
                    metadata: .strip,
                    colorSpace: .preserve
                )
            )
        )
        let outputInfo = try Self.imageInfo(outputData)

        #expect(inputInfo.orientation == 6)
        #expect(inputInfo.hasGPS == false)
        #expect(outputInfo.orientation == 1)
        #expect(outputInfo.displayWidth == inputInfo.displayWidth)
        #expect(outputInfo.displayHeight == inputInfo.displayHeight)
    }

    // Ordinary metadata preservation does not preserve auxiliary HDR gain maps.
    @available(iOS 14.1, macOS 11.0, *)
    @Test("Process metadata preservation drops the HDR gain map")
    func processMetadataPreservationDropsGainMap() throws {
        let url = try Self.resource("real_heic_4032x3024_o1_gps_hdr", extension: "heic")
        let inputData = try Data(contentsOf: url)

        try #require(Self.hasGainMap(inputData), "Fixture should contain an HDR gain map")

        let outputData = try WICompress.process(
            inputData,
            using: WIImageProcess(
                sizing: .resize(using: WIImageResize.luban),
                quality: 0.6,
                output: WIImageOutput(
                    representation: .preserve,
                    metadata: .preserve,
                    colorSpace: .preserve
                )
            )
        )

        #expect(Self.hasGainMap(outputData) == false)
    }

    @Test("Animated images are rejected")
    func animatedImageThrows() throws {
        let url = try Self.resource("real_gif_555x555_4frames", extension: "gif")
        let inputData = try Data(contentsOf: url)

        #expect(throws: WICompressError.animatedSourceUnsupported(frameCount: 4)) {
            _ = try WICompress.process(inputData)
        }
    }
}
