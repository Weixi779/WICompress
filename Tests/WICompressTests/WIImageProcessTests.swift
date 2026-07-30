//
//  WIImageProcessTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/7/30.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import WICompress
@testable import WICompressExecution
@testable import WIImageDomain

@Suite("WIImageProcess", .tags(.imageProcess, .publicAPI))
struct WIImageProcessTests {
    private struct FixedResizing: WIImageResizing {
        let size: WIPixelSize

        func targetSize(for sourceSize: WIPixelSize) -> WIPixelSize {
            size
        }
    }

    @Test(
        "Built-in resizing returns complete proportional sizes",
        arguments: [
            (
                WIImageResize.maximumPixelSize(400),
                WIPixelSize(width: 1_000, height: 500),
                WIPixelSize(width: 400, height: 200)
            ),
            (
                WIImageResize.constrained(
                    within: WIPixelSize(width: 400, height: 400)
                ),
                WIPixelSize(width: 1_000, height: 500),
                WIPixelSize(width: 400, height: 200)
            ),
            (
                WIImageResize.constrained(
                    within: WIPixelSize(width: 2_000, height: 2_000)
                ),
                WIPixelSize(width: 1_000, height: 500),
                WIPixelSize(width: 1_000, height: 500)
            ),
            (
                WIImageResize.constrained(
                    within: WIPixelSize(width: 2_000, height: 2_000),
                    allowingUpscaling: true
                ),
                WIPixelSize(width: 1_000, height: 500),
                WIPixelSize(width: 2_000, height: 1_000)
            ),
            (
                WIImageResize.scaled(by: 0.5),
                WIPixelSize(width: 1_000, height: 500),
                WIPixelSize(width: 500, height: 250)
            ),
            (
                WIImageResize.exact(WIPixelSize(width: 600, height: 600)),
                WIPixelSize(width: 1_000, height: 500),
                WIPixelSize(width: 600, height: 600)
            ),
        ]
    )
    func builtInResizing(
        _ resizing: WIImageResize,
        source: WIPixelSize,
        expected: WIPixelSize
    ) {
        #expect(resizing.targetSize(for: source) == expected)
    }

    @Test(
        "Public Luban resizing returns frozen target sizes",
        arguments: [
            (
                WIPixelSize(width: 3_000, height: 2_000),
                WIPixelSize(width: 1_500, height: 1_000)
            ),
            (
                WIPixelSize(width: 1_440, height: 3_200),
                WIPixelSize(width: 720, height: 1_600)
            ),
        ]
    )
    func lubanTargetSize(
        source: WIPixelSize,
        expected: WIPixelSize
    ) {
        #expect(
            WIImageResize.luban.targetSize(for: source) == expected
        )
    }

    @Test(
        "Aspect-ratio crop resolves in oriented top-left coordinates",
        arguments: [
            (
                WIImageCrop.aspectRatio(width: 1, height: 1),
                Rect(x: 500, y: 0, width: 3_000, height: 3_000)
            ),
            (
                WIImageCrop.aspectRatio(
                    width: 1,
                    height: 1,
                    anchor: WICropAnchor(x: 0, y: 0.5)
                ),
                Rect(x: 0, y: 0, width: 3_000, height: 3_000)
            ),
            (
                WIImageCrop.aspectRatio(
                    width: 16,
                    height: 9,
                    anchor: WICropAnchor(x: 0.5, y: 1)
                ),
                Rect(x: 0, y: 750, width: 4_000, height: 2_250)
            ),
        ]
    )
    func aspectRatioCrop(
        _ crop: WIImageCrop,
        expected: Rect
    ) throws {
        let geometry = try WIImageProcessGeometry.resolve(
            process: WIImageProcess(
                sizing: .original,
                crop: crop,
                quality: nil
            ),
            sourcePixelSize: WIPixelSize(width: 4_000, height: 3_000)
        )

        #expect(geometry.sourceRect == expected)
        #expect(
            geometry.targetPixelSize
                == WIPixelSize(
                    width: Int(expected.width),
                    height: Int(expected.height)
                )
        )
    }

    @Test("Resizing receives the cropped pixel size")
    func resizingReceivesCroppedPixelSize() throws {
        struct HalfSize: WIImageResizing {
            func targetSize(for sourceSize: WIPixelSize) -> WIPixelSize {
                WIPixelSize(
                    width: sourceSize.width / 2,
                    height: sourceSize.height / 2
                )
            }
        }

        let geometry = try WIImageProcessGeometry.resolve(
            process: WIImageProcess(
                sizing: .resize(using: HalfSize()),
                crop: .aspectRatio(width: 1, height: 1),
                quality: nil
            ),
            sourcePixelSize: WIPixelSize(width: 4_000, height: 3_000)
        )

        #expect(
            geometry.croppedPixelSize
                == WIPixelSize(width: 3_000, height: 3_000)
        )
        #expect(
            geometry.targetPixelSize
                == WIPixelSize(width: 1_500, height: 1_500)
        )
    }

    @Test("Invalid Process inputs fail instead of being clamped")
    func invalidInputsFail() throws {
        let data = try Self.resourceData(
            "real_jpeg_2098x1350_landscape",
            extension: "jpg"
        )

        #expect(throws: WICompressError.invalidProcessQuality) {
            try WICompressor.process(
                data,
                using: WIImageProcess(quality: 1.1)
            )
        }
        #expect(throws: WICompressError.invalidCrop) {
            try WICompressor.process(
                data,
                using: WIImageProcess(
                    crop: .aspectRatio(width: 0, height: 1)
                )
            )
        }
        #expect(throws: WICompressError.invalidResizingResult) {
            try WICompressor.process(
                data,
                using: WIImageProcess(
                    sizing: .resize(
                        using: FixedResizing(
                            size: WIPixelSize(width: 0, height: 100)
                        )
                    )
                )
            )
        }
    }

    @Test(
        "Unexecutable resizing results fail at the geometry boundary",
        arguments: [
            WIPixelSize(width: .max, height: 1),
            WIPixelSize(width: 1, height: .max),
        ]
    )
    func unexecutableResizingResultFails(_ size: WIPixelSize) {
        #expect(throws: WICompressError.invalidResizingResult) {
            try WIImageProcessGeometry.resolve(
                process: WIImageProcess(
                    sizing: .resize(
                        using: FixedResizing(size: size)
                    )
                ),
                sourcePixelSize: WIPixelSize(width: 400, height: 100)
            )
        }
    }

    @Test("Process applies a custom resizing result")
    func processAppliesCustomResizing() throws {
        let data = try Self.resourceData(
            "real_jpeg_2098x1350_landscape",
            extension: "jpg"
        )
        let result = try WICompressor.process(
            data,
            using: WIImageProcess(
                sizing: .resize(
                    using: FixedResizing(
                        size: WIPixelSize(width: 320, height: 180)
                    )
                ),
                quality: 0.7
            )
        )
        let outputSource = try WIImageSource(data: result.data)

        #expect(result.pixelSize == WIPixelSize(width: 320, height: 180))
        #expect(result.format == .jpeg)
        #expect(result.byteCount == result.data.count)
        #expect(outputSource.descriptor.orientedPixelSize == result.pixelSize)
        #expect(outputSource.descriptor.format == result.format)
    }

    @Test("Process crop fixes the encoded aspect ratio before resizing")
    func processAppliesCropBeforeResizing() throws {
        let data = try Self.resourceData(
            "real_jpeg_2098x1350_landscape",
            extension: "jpg"
        )
        let output = try WICompressor.process(
            data,
            using: WIImageProcess(
                sizing: .resize(
                    using: WIImageResize.exact(
                        WIPixelSize(width: 512, height: 512)
                    )
                ),
                crop: .aspectRatio(width: 1, height: 1),
                quality: nil,
                output: WIImageOutput(representation: .png)
            )
        ).data
        let outputSource = try WIImageSource(data: output)

        #expect(outputSource.descriptor.orientedPixelSize.width == 512)
        #expect(outputSource.descriptor.orientedPixelSize.height == 512)
        #expect(outputSource.descriptor.format == .png)
    }

    @Test("Non-center Process crop uses EXIF-oriented coordinates")
    func nonCenterCropUsesOrientedCoordinates() throws {
        let input = try Self.orientedGrayscaleBandsJPEG(
            width: 8,
            height: 4,
            orientation: 6
        )
        let oracle = try Self.imageIOOrientedPNG(input)
        let output = try WICompressor.process(
            input,
            using: WIImageProcess(
                sizing: .original,
                crop: .aspectRatio(
                    width: 1,
                    height: 1,
                    anchor: WICropAnchor(x: 0.5, y: 0)
                ),
                quality: nil,
                output: WIImageOutput(representation: .png)
            )
        ).data
        let outputRed = try Self.redValues(in: output, x: 2)
        let oracleRed = try Self.redValues(in: oracle, x: 2)
        let keptDifferences = zip(
            outputRed,
            oracleRed.prefix(outputRed.count)
        ).map { abs(Int($0) - Int($1)) }
        let discardedDifferences = zip(
            outputRed,
            oracleRed.suffix(outputRed.count)
        ).map { abs(Int($0) - Int($1)) }

        #expect(outputRed.count == 4)
        #expect(oracleRed.count == 8)
        #expect((keptDifferences.max() ?? .max) <= 32)
        #expect((discardedDifferences.max() ?? 0) >= 64)
    }

    @Test("Aspect-changing resize preserves samples required by both axes")
    func aspectChangingResizePreservesRequiredSamples() throws {
        let input = try Self.horizontalStripesPNG(width: 400, height: 100)
        let output = try WICompressor.process(
            input,
            using: WIImageProcess(
                sizing: .resize(
                    using: WIImageResize.exact(
                        WIPixelSize(width: 100, height: 100)
                    )
                ),
                quality: nil,
                output: WIImageOutput(representation: .png)
            )
        ).data
        let redValues = try Self.redValues(in: output, x: 50)
        let transitions = zip(redValues, redValues.dropFirst())
            .count { first, second in
                abs(Int(first) - Int(second)) > 128
            }

        #expect(transitions >= 40)
    }

    @Test("Alpha-aware representation selects PNG")
    func alphaAwareRepresentationSelectsPNG() throws {
        let data = try Self.resourceData(
            "real_png_1086x1630_alpha",
            extension: "png"
        )
        let output = try WICompressor.process(
            data,
            using: WIImageProcess(
                sizing: .original,
                quality: 0.5,
                output: WIImageOutput(
                    representation: .pngIfAlphaOtherwiseJPEG
                )
            )
        ).data

        #expect(try WIImageSource(data: output).descriptor.format == .png)
    }

    @Test("Transparent sources require an explicit JPEG background")
    func transparentJPEGRequiresBackground() throws {
        let data = try Self.resourceData(
            "real_png_1086x1630_alpha",
            extension: "png"
        )

        #expect(
            throws: WICompressError.transparentSourceRequiresBackground(.png)
        ) {
            try WICompressor.process(
                data,
                using: WIImageProcess(
                    output: WIImageOutput(representation: .jpeg())
                )
            )
        }
    }

    @Test("A fully satisfied Process returns the original bytes")
    func satisfiedProcessReturnsOriginal() throws {
        let data = try Self.resourceData(
            "synthetic_tiny_1x1",
            extension: "png"
        )
        let output = try WICompressor.process(
            data,
            using: WIImageProcess(
                sizing: .original,
                quality: nil,
                output: WIImageOutput(metadata: .preserve)
            )
        ).data

        #expect(output == data)
    }

    @Test("Declaring a crop requires rendering even when its ratio already matches")
    func declaredCropRequiresRendering() throws {
        let data = try Self.resourceData(
            "synthetic_tiny_1x1",
            extension: "png"
        )
        let source = try WIImageSource(data: data)
        let plan = try WIImageProcessResolver.resolve(
            WIImageProcess(
                sizing: .original,
                crop: .aspectRatio(width: 1, height: 1),
                quality: nil,
                output: WIImageOutput(metadata: .preserve)
            ),
            imageSource: source
        )

        guard case .render = plan.operation else {
            Issue.record("A declared crop must not use passthrough")
            return
        }
    }

    @Test("Process preserves selected metadata while baking orientation")
    func processPreservesMetadata() throws {
        let data = try Self.resourceData(
            "real_heic_4032x3024_o6_gps_hdr",
            extension: "heic"
        )
        let output = try WICompressor.process(
            data,
            using: WIImageProcess(
                sizing: .resize(
                    using: WIImageResize.maximumPixelSize(512)
                ),
                quality: 0.7,
                output: WIImageOutput(
                    representation: .jpeg(),
                    metadata: .preserve
                )
            )
        ).data
        let outputSource = try WIImageSource(data: output)

        #expect(outputSource.descriptor.hasGPS)
        #expect(outputSource.descriptor.orientation == .up)
        #expect(outputSource.descriptor.format == .jpeg)
    }

    @Test("Process converts rendered pixels to sRGB")
    func processConvertsColorSpace() throws {
        let data = try Self.resourceData(
            "real_heic_4032x3024_o1_gps_hdr",
            extension: "heic"
        )
        let output = try WICompressor.process(
            data,
            using: WIImageProcess(
                sizing: .resize(
                    using: WIImageResize.maximumPixelSize(512)
                ),
                quality: 0.7,
                output: WIImageOutput(
                    representation: .jpeg(),
                    colorSpace: .convert(to: .sRGB)
                )
            )
        ).data
        let outputSource = try WIImageSource(data: output)

        #expect(try outputSource.sourceColorSpace() == .sRGB)
    }

    @Test("Data and file Process terminals have equivalent behavior")
    func dataAndFileTerminalsAreEquivalent() throws {
        let data = try Self.resourceData(
            "real_jpeg_2098x1350_landscape",
            extension: "jpg"
        )
        let process = WIImageProcess(
            sizing: .resize(
                using: WIImageResize.maximumPixelSize(320)
            ),
            quality: 0.7
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("source.jpg")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try data.write(to: url)

        let fileSource = try WIImageSource(contentsOf: url)
        guard case .file(let backingURL) = fileSource.backing else {
            Issue.record("The file terminal must keep a file-backed source")
            return
        }
        #expect(backingURL == url)

        let dataResult = try WICompressor.process(data, using: process)
        let fileResult = try WICompressor.process(
            contentsOf: url,
            using: process
        )

        #expect(fileResult.data == dataResult.data)
        #expect(fileResult.format == dataResult.format)
        #expect(fileResult.pixelSize == dataResult.pixelSize)
        #expect(fileResult.byteCount == dataResult.byteCount)
    }

    @Test("File-backed sources load original bytes only on demand")
    func fileBackedSourceLoadsOriginalOnDemand() throws {
        let data = try Self.resourceData(
            "synthetic_tiny_1x1",
            extension: "png"
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("source.png")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try data.write(to: url)

        let source = try WIImageSource(contentsOf: url)
        try FileManager.default.removeItem(at: url)

        #expect(throws: WICompressError.fileReadFailed(url)) {
            try source.originalData()
        }
    }

    private static func horizontalStripesPNG(
        width: Int,
        height: Int
    ) throws -> Data {
        var pixels = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        for y in 0..<height {
            let value: UInt8 = (y / 2).isMultiple(of: 2) ? 0 : 255
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
                pixels[index + 3] = 255
            }
        }

        let provider = try #require(
            CGDataProvider(data: Data(pixels) as CFData)
        )
        let image = try #require(
            CGImage(
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
        )
        return try pngData(image)
    }

    private static func orientedGrayscaleBandsJPEG(
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
        let bandWidth = CGFloat(width) / 4
        for (index, value) in [0.0, 0.33, 0.66, 1.0].enumerated() {
            context.setFillColor(
                CGColor(
                    red: value,
                    green: value,
                    blue: value,
                    alpha: 1
                )
            )
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
            [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationLossyCompressionQuality: 1,
            ] as CFDictionary
        )
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func imageIOOrientedPNG(_ data: Data) throws -> Data {
        let source = try #require(
            CGImageSourceCreateWithData(data as CFData, nil)
        )
        let image = try #require(
            CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 8,
                ] as CFDictionary
            )
        )
        return try pngData(image)
    }

    private static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                data,
                "public.png" as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func redValues(
        in data: Data,
        x: Int
    ) throws -> [UInt8] {
        let source = try #require(
            CGImageSourceCreateWithData(data as CFData, nil)
        )
        let image = try #require(
            CGImageSourceCreateImageAtIndex(source, 0, nil)
        )
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var pixels = [UInt8](
            repeating: 0,
            count: image.height * bytesPerRow
        )
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                )
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

        let resolvedX = min(max(x, 0), image.width - 1)
        return (0..<image.height).map { y in
            pixels[y * bytesPerRow + resolvedX * bytesPerPixel]
        }
    }

    private static func resourceData(
        _ name: String,
        extension ext: String
    ) throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Resources"
            )
        )
        return try Data(contentsOf: url)
    }
}
