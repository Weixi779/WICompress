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
