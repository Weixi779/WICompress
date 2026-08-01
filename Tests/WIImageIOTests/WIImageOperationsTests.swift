//
//  WIImageOperationsTests.swift
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
@testable import WIImageIO

extension Tag {
    @Tag static var imageIOCore: Self
}

@Suite("WIImageIO Operations", .tags(.imageIOCore))
struct WIImageOperationsTests {
    @Test("Data inspection exposes typed, orientation-aware facts")
    func dataDescriptor() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true,
            hasTIFFOrientation: true
        )
        let descriptor = try WIImageIO.inspect(data)

        #expect(descriptor.byteCount == data.count)
        #expect(descriptor.type == .jpeg)
        #expect(descriptor.format == .jpeg)
        #expect(descriptor.pixelSize.width == 40)
        #expect(descriptor.pixelSize.height == 20)
        #expect(
            descriptor.pixelSize.width * descriptor.pixelSize.height == 800
        )
        #expect(descriptor.orientedPixelSize.width == 20)
        #expect(descriptor.orientedPixelSize.height == 40)
        #expect(descriptor.orientation == .right)
        #expect(descriptor.frameCount == 1)
        #expect(descriptor.hasAlpha != true)
        #expect(descriptor.metadata.contains(.gps))
        #expect(WIImageIO.canDecode(.jpeg))
        #expect(WIImageIO.canEncode(.jpeg))
    }

    @Test("File inspection preserves the encoded byte count")
    func fileDescriptor() throws {
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

        let descriptor = try WIImageIO.inspect(contentsOf: url)

        #expect(descriptor.byteCount == data.count)
        #expect(descriptor.format == .png)
        #expect(descriptor.pixelSize.width == 12)
        #expect(descriptor.pixelSize.height == 8)
    }

    @Test("Transparent PNG reports alpha")
    func transparentPNGReportsAlpha() throws {
        let data = try Self.encodedImage(
            width: 4,
            height: 4,
            typeIdentifier: UTType.png.identifier,
            alpha: 96
        )

        let descriptor = try WIImageIO.inspect(data)

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

        let reader = try WIImageIO.read(data)
        let descriptor = reader.descriptor

        #expect(descriptor.frameCount == 2)
        #expect(descriptor.format == .unknown)
        #expect(!reader.canTranscode(as: .png))
        #expect(throws: WIImageIO.Error.animatedSourceUnsupported(frameCount: 2)) {
            try WIImageIO.read(data).image()
        }
        #expect(throws: WIImageIO.Error.animatedSourceUnsupported(frameCount: 2)) {
            try WIImageIO.read(data).thumbnail()
        }
        #expect(throws: WIImageIO.Error.animatedSourceUnsupported(frameCount: 2)) {
            try WIImageIO.read(data).transcode(as: .png)
        }
    }

    @Test("Data and file inputs have equivalent decode and transcode semantics")
    func dataAndFileParity() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true,
            hasTIFFOrientation: true
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let dataReader = try WIImageIO.read(data)
        let fileReader = try WIImageIO.read(contentsOf: url)
        let dataDescriptor = dataReader.descriptor
        let fileDescriptor = fileReader.descriptor
        let dataImage = try dataReader.image().image
        let fileImage = try fileReader.image().image
        let thumbnailOptions = WIImageIO.ThumbnailOptions(maximumPixelSize: 10)
        let dataThumbnail = try dataReader.thumbnail(
            options: thumbnailOptions
        ).image
        let fileThumbnail = try fileReader.thumbnail(
            options: thumbnailOptions
        ).image
        let dataTranscode = try WIImageIO.inspect(
            dataReader.transcode(as: .jpeg)
        )
        let fileTranscode = try WIImageIO.inspect(
            fileReader.transcode(as: .jpeg)
        )

        #expect(dataDescriptor == fileDescriptor)
        #expect(dataImage.width == fileImage.width)
        #expect(dataImage.height == fileImage.height)
        #expect(dataThumbnail.width == fileThumbnail.width)
        #expect(dataThumbnail.height == fileThumbnail.height)
        #expect(dataTranscode.format == fileTranscode.format)
        #expect(dataTranscode.pixelSize == fileTranscode.pixelSize)
        #expect(dataTranscode.orientedPixelSize == fileTranscode.orientedPixelSize)
        #expect(dataTranscode.orientation == fileTranscode.orientation)
        #expect(dataTranscode.metadata == fileTranscode.metadata)
    }

    @Test("Image decode returns source pixel dimensions")
    func imageDecode() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier
        )

        let decodedFrame = try WIImageIO.read(data).image(
            options: WIImageIO.DecodeOptions(cacheImmediately: false)
        )

        #expect(decodedFrame.image.width == 40)
        #expect(decodedFrame.image.height == 20)
        #expect(decodedFrame.orientation == .up)
    }

    @Test("Thumbnail applies orientation and respects the maximum pixel size")
    func orientedThumbnail() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6
        )

        let result = try WIImageIO.read(data).thumbnail(
            options: WIImageIO.ThumbnailOptions(maximumPixelSize: 10)
        )

        #expect(result.image.width == 5)
        #expect(result.image.height == 10)
        #expect(result.orientation == .up)
    }

    @Test("Transcode preserves metadata and orientation coupling")
    func transcodedMetadata() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true
        )

        let transcodedData = try WIImageIO.read(data).transcode(as: .jpeg)
        let properties = try Self.properties(in: transcodedData)

        #expect(properties.intValue(for: kCGImagePropertyOrientation) == 6)
        #expect(properties[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test("Transcode can remove GPS metadata without decoding pixels")
    func transcodeExcludingGPS() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true
        )
        let metadata = WIImageMetadataOptions.preserve.subtracting(.gps)

        let transcodedData = try WIImageIO.read(data).transcode(
            as: .jpeg,
            options: WIImageIO.TranscodeOptions(metadata: metadata)
        )
        let properties = try Self.properties(in: transcodedData)

        #expect(properties.intValue(for: kCGImagePropertyOrientation) == 6)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)

        let incompatibleOptions = WIImageIO.TranscodeOptions(
            maximumPixelSize: 10,
            metadata: metadata
        )
        let reader = try WIImageIO.read(data)
        #expect(!reader.canTranscode(as: .jpeg, options: incompatibleOptions))
        #expect(throws: WIImageIO.Error.metadataTranscodeUnsupported(.jpeg)) {
            try reader.transcode(as: .jpeg, options: incompatibleOptions)
        }
    }

    @Test("Inspection distinguishes metadata outside the public categories")
    func unmodeledMetadataInspection() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.png.identifier,
            pngAuthor: "WICompress"
        )
        let reader = try WIImageIO.read(data)
        let descriptor = reader.descriptor

        #expect(descriptor.hasUnmodeledMetadata)
        #expect(!reader.canTranscode(
            as: .png,
            options: WIImageIO.TranscodeOptions(metadata: .strip)
        ))
        #expect(reader.canTranscode(
            as: .png,
            options: WIImageIO.TranscodeOptions(metadata: .preserve)
        ))
    }

    @Test("Pixel encode strips metadata or preserves selected source metadata")
    func pixelEncodeMetadata() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true,
            hasTIFFOrientation: true
        )
        let decodedFrame = try WIImageIO.read(data).thumbnail()

        let strippedData = try decodedFrame.encode(as: .jpeg)
        let preservedData = try decodedFrame.encode(
            as: .jpeg,
            options: WIImageIO.EncodeOptions(metadata: .preserve)
        )
        let strippedProperties = try Self.properties(in: strippedData)
        let preservedProperties = try Self.properties(in: preservedData)

        #expect(strippedProperties[kCGImagePropertyGPSDictionary] == nil)
        #expect(preservedProperties[kCGImagePropertyGPSDictionary] != nil)
        #expect(preservedProperties.intValue(for: kCGImagePropertyOrientation) == 1)
        let tiff = preservedProperties[
            kCGImagePropertyTIFFDictionary
        ] as? [CFString: Any]
        #expect(tiff?.intValue(for: kCGImagePropertyTIFFOrientation) != 6)
    }

    @Test("Decoded frames snapshot metadata without retaining their Reader")
    func frameMetadataLifetime() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6,
            hasGPS: true
        )

        weak var releasedReader: WIImageIO.Reader?
        let frame: WIImageIO.Frame
        do {
            let reader = try WIImageIO.read(data)
            releasedReader = reader
            frame = try reader.thumbnail()
        }

        #expect(releasedReader == nil)

        let encoded = try frame.encode(
            as: .jpeg,
            options: WIImageIO.EncodeOptions(metadata: .preserve)
        )
        let properties = try Self.properties(in: encoded)
        #expect(properties[kCGImagePropertyGPSDictionary] != nil)
        #expect(properties.intValue(for: kCGImagePropertyOrientation) == 1)
    }

    @Test("Decoded frame keeps orientation through chained encode")
    func decodedFrameOrientationRoundTrip() throws {
        let data = try Self.encodedImage(
            width: 40,
            height: 20,
            typeIdentifier: UTType.jpeg.identifier,
            orientation: 6
        )

        let frame = try WIImageIO.read(data).image()
        let output = try frame.encode(as: .jpeg)
        let properties = try Self.properties(in: output)

        #expect(frame.orientation == .right)
        #expect(frame.pixelSize == WIPixelSize(width: 40, height: 20))
        #expect(properties.intValue(for: kCGImagePropertyOrientation) == 6)
    }

    @Test("Exif and MakerNote remain independent metadata categories")
    func exifAndMakerNoteSelection() {
        let makerNote = Data([0x41, 0x70, 0x70, 0x6C, 0x65])
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 1.0 / 60.0,
                kCGImagePropertyExifMakerNote: makerNote
            ],
            kCGImagePropertyMakerAppleDictionary: [
                "17": 1
            ]
        ]

        let options = WIImageIO.metadataOptions(in: properties)
        let exifOnly = WIImageIO.metadataProperties(
            in: properties,
            keeping: .exif
        )
        let makerNotesOnly = WIImageIO.metadataProperties(
            in: properties,
            keeping: .makerNotes
        )
        let exifOnlyDictionary = exifOnly[
            kCGImagePropertyExifDictionary
        ] as? [AnyHashable: Any]
        let makerNotesOnlyDictionary = makerNotesOnly[
            kCGImagePropertyExifDictionary
        ] as? [AnyHashable: Any]

        #expect(options.contains(.exif))
        #expect(options.contains(.makerNotes))
        #expect(
            exifOnlyDictionary?[kCGImagePropertyExifExposureTime] != nil
        )
        #expect(
            exifOnlyDictionary?[kCGImagePropertyExifMakerNote] == nil
        )
        #expect(
            exifOnly[kCGImagePropertyMakerAppleDictionary] == nil
        )
        #expect(
            makerNotesOnlyDictionary?[kCGImagePropertyExifExposureTime] == nil
        )
        #expect(
            makerNotesOnlyDictionary?[kCGImagePropertyExifMakerNote] as? Data
                == makerNote
        )
        #expect(
            makerNotesOnly[kCGImagePropertyMakerAppleDictionary] != nil
        )
    }

    @Test("Inspection ignores metadata fields excluded from output")
    func metadataInspectionUsesFilteredProjection() {
        let makerNote = Data([0x41, 0x70, 0x70, 0x6C, 0x65])
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifMakerNote: makerNote
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFOrientation: 6
            ],
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCImageOrientation: "L"
            ]
        ]

        let options = WIImageIO.metadataOptions(in: properties)

        #expect(options == .makerNotes)
    }

    @Test("Unsupported destinations fail before encoding")
    func unsupportedDestination() throws {
        let data = try Self.encodedImage(
            width: 4,
            height: 4,
            typeIdentifier: UTType.png.identifier
        )
        let type = UTType(exportedAs: "com.wicompress.unsupported")

        #expect(throws: WIImageIO.Error.imageEncodeFailed(type)) {
            try WIImageIO.read(data).transcode(as: type)
        }
    }

    @Test("Invalid encoded bytes fail explicitly")
    func invalidDataFails() {
        #expect(throws: WIImageIO.Error.invalidImageData) {
            try WIImageIO.inspect(Data([0x00, 0x01, 0x02]))
        }
    }

    @Test("Missing file reports a typed read error")
    func missingFileFails() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        #expect(throws: WIImageIO.Error.fileReadFailed(url)) {
            try WIImageIO.inspect(contentsOf: url)
        }
    }

    private static func encodedImage(
        width: Int,
        height: Int,
        typeIdentifier: String,
        orientation: Int = 1,
        hasGPS: Bool = false,
        hasTIFFOrientation: Bool = false,
        pngAuthor: String? = nil,
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
        if hasTIFFOrientation {
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFOrientation: orientation
            ]
        }
        if let pngAuthor {
            properties[kCGImagePropertyPNGDictionary] = [
                kCGImagePropertyPNGAuthor: pngAuthor
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
