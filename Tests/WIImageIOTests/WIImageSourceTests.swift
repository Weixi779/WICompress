//
//  WIImageSourceTests.swift
//  WIImageIOTests
//
//  Created by weixi on 2026/7/29.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WIImageCore
@testable import WIImageIO

extension Tag {
    @Tag static var imageIOCore: Self
}

@Suite("WIImageIO Source", .tags(.imageIOCore))
struct WIImageSourceTests {
    @Test("Data source exposes typed, orientation-aware facts")
    func dataSourceDescriptor() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true
        )
        let source = try Source(data: data)
        let descriptor = source.descriptor

        #expect(source.byteCount == data.count)
        #expect(descriptor.byteCount == data.count)
        #expect(descriptor.format == .jpeg)
        #expect(descriptor.pixelSize.width == 40)
        #expect(descriptor.pixelSize.height == 20)
        #expect(descriptor.pixelSize.pixelCount == 800)
        #expect(descriptor.orientedPixelSize.width == 20)
        #expect(descriptor.orientedPixelSize.height == 40)
        #expect(descriptor.orientation == .right)
        #expect(descriptor.frameCount == 1)
        #expect(descriptor.hasAlpha != true)
        #expect(descriptor.hasMetadata)
        #expect(descriptor.hasGPS)
        #expect(descriptor.isSourceFormatDecodable)
        #expect(descriptor.isSourceFormatWritable)
    }

    @Test("File source inspects without changing encoded byte count")
    func fileSourceDescriptor() throws {
        let data = try Self.encodedImage(
            width: 12,
            height: 8,
            typeIdentifier: UTType.png.identifier
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = try Source(contentsOf: url)

        #expect(source.byteCount == data.count)
        #expect(source.descriptor.byteCount == data.count)
        #expect(source.descriptor.format == .png)
        #expect(source.descriptor.pixelSize.width == 12)
        #expect(source.descriptor.pixelSize.height == 8)
    }

    @Test("Transparent PNG reports alpha")
    func transparentPNGReportsAlpha() throws {
        let data = try Self.encodedImage(
            width: 4,
            height: 4,
            typeIdentifier: UTType.png.identifier,
            alpha: 96
        )

        let descriptor = try Source(data: data).descriptor

        #expect(descriptor.hasAlpha == true)
    }

    @Test("Inspection reports every frame without imposing a product policy")
    func multiFrameDescriptor() throws {
        let data = try Self.encodedImage(
            width: 4,
            height: 4,
            typeIdentifier: UTType.gif.identifier,
            frameCount: 2
        )

        let source = try Source(data: data)
        let descriptor = source.descriptor

        #expect(descriptor.frameCount == 2)
        #expect(descriptor.format == .unknown)
        #expect(throws: WIImageIO.Error.animatedSourceUnsupported(frameCount: 2)) {
            try source.image()
        }
        #expect(throws: WIImageIO.Error.animatedSourceUnsupported(frameCount: 2)) {
            try source.thumbnail(options: ThumbnailOptions())
        }
        #expect(throws: WIImageIO.Error.animatedSourceUnsupported(frameCount: 2)) {
            try source.copy(as: UTType.png.identifier)
        }
    }

    @Test("Data and file sources have equivalent decode and copy semantics")
    func dataAndFileSourceParity() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let dataSource = try Source(data: data)
        let fileSource = try Source(contentsOf: url)
        let dataImage = try dataSource.image()
        let fileImage = try fileSource.image()
        let dataThumbnail = try dataSource.thumbnail(
            options: ThumbnailOptions(maximumPixelSize: 10)
        )
        let fileThumbnail = try fileSource.thumbnail(
            options: ThumbnailOptions(maximumPixelSize: 10)
        )
        let dataCopy = try Source(
            data: dataSource.copy(as: UTType.jpeg.identifier)
        ).descriptor
        let fileCopy = try Source(
            data: fileSource.copy(as: UTType.jpeg.identifier)
        ).descriptor

        #expect(dataSource.descriptor == fileSource.descriptor)
        #expect(dataImage.width == fileImage.width)
        #expect(dataImage.height == fileImage.height)
        #expect(dataThumbnail.width == fileThumbnail.width)
        #expect(dataThumbnail.height == fileThumbnail.height)
        #expect(dataCopy.format == fileCopy.format)
        #expect(dataCopy.pixelSize == fileCopy.pixelSize)
        #expect(dataCopy.orientedPixelSize == fileCopy.orientedPixelSize)
        #expect(dataCopy.orientation == fileCopy.orientation)
        #expect(dataCopy.hasGPS == fileCopy.hasGPS)
    }

    @Test("Image decode returns source pixel dimensions")
    func imageDecode() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier
        )

        let image = try Source(data: data).image(
            options: DecodeOptions(cacheImmediately: false)
        )

        #expect(image.width == 40)
        #expect(image.height == 20)
    }

    @Test("Thumbnail applies orientation and respects the maximum pixel size")
    func orientedThumbnail() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6
        )

        let thumbnail = try Source(data: data).thumbnail(
            options: ThumbnailOptions(maximumPixelSize: 10)
        )

        #expect(thumbnail.width == 5)
        #expect(thumbnail.height == 10)
    }

    @Test("Source copy preserves metadata and orientation coupling")
    func sourceCopy() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true
        )

        let copiedData = try Source(data: data).copy(
            as: UTType.jpeg.identifier
        )
        let properties = try Self.properties(in: copiedData)

        #expect(properties.intValue(for: kCGImagePropertyOrientation) == 6)
        #expect(properties[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test("Pixel encode strips metadata or preserves selected source metadata")
    func pixelEncodeMetadata() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true
        )
        let source = try Source(data: data)
        let image = try source.thumbnail(options: ThumbnailOptions())

        let strippedData = try Transcoder.encode(
            image,
            as: UTType.jpeg.identifier
        )
        let preservedData = try Transcoder.encode(
            image,
            as: UTType.jpeg.identifier,
            preservingMetadataFrom: source
        )
        let strippedProperties = try Self.properties(in: strippedData)
        let preservedProperties = try Self.properties(in: preservedData)

        #expect(strippedProperties[kCGImagePropertyGPSDictionary] == nil)
        #expect(preservedProperties[kCGImagePropertyGPSDictionary] != nil)
        #expect(preservedProperties.intValue(for: kCGImagePropertyOrientation) == 1)
    }

    @Test("Unsupported destinations fail before encoding")
    func unsupportedDestination() throws {
        let data = try Self.encodedImage(
            width: 4,
            height: 4,
            typeIdentifier: UTType.png.identifier
        )
        let source = try Source(data: data)
        let typeIdentifier = "com.wicompress.unsupported"

        #expect(throws: WIImageIO.Error.destinationCreationFailed(typeIdentifier)) {
            try source.copy(as: typeIdentifier)
        }
    }

    @Test("Invalid encoded bytes fail explicitly")
    func invalidDataFails() {
        #expect(throws: WIImageIO.Error.invalidImageData) {
            try Source(data: Data([0x00, 0x01, 0x02]))
        }
    }

    @Test("Missing file reports a typed read error")
    func missingFileFails() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        #expect(throws: WIImageIO.Error.fileReadFailed(url)) {
            try Source(contentsOf: url)
        }
    }

    private static func encodedImage(
        width: Int,
        height: Int,
        typeIdentifier: String,
        orientation: Int = 1,
        hasGPS: Bool = false,
        alpha: UInt8 = 255,
        frameCount: Int = 1
    ) throws -> Data {
        let image = try #require(bitmap(width: width, height: height, alpha: alpha))
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                data,
                typeIdentifier as CFString,
                frameCount,
                nil
            )
        )

        var properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation
        ]
        if hasGPS {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLatitude: 31.2,
                kCGImagePropertyGPSLongitudeRef: "E",
                kCGImagePropertyGPSLongitude: 121.5
            ]
        }

        for _ in 0..<frameCount {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func properties(in data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
    }

    private static func bitmap(width: Int, height: Int, alpha: UInt8) -> CGImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 40
            pixels[index + 1] = 120
            pixels[index + 2] = 220
            pixels[index + 3] = alpha
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

private extension Dictionary where Key == CFString, Value == Any {
    func intValue(for key: CFString) -> Int? {
        if let value = self[key] as? Int {
            return value
        }

        return (self[key] as? NSNumber)?.intValue
    }
}
