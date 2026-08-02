//
//  ExampleImage.swift
//  WICompressExample
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import UIKit
import WICompress
import WIImageIO

struct ExampleImage {
    enum ByteCountChange {
        case smaller(percentage: Double)
        case unchanged
        case larger(percentage: Double)

        var text: String {
            switch self {
            case .smaller(let percentage):
                "\(percentage.formatted(.number.precision(.fractionLength(1))))% smaller"
            case .unchanged:
                "No size change"
            case .larger(let percentage):
                "\(percentage.formatted(.number.precision(.fractionLength(1))))% larger"
            }
        }
    }

    struct Content: Sendable {
        let data: Data
        let preview: CGImage
        let format: ImageFormat
        let pixelSize: WIPixelSize
    }

    let data: Data
    let preview: UIImage
    let format: ImageFormat
    let pixelSize: WIPixelSize

    var byteCount: Int {
        data.count
    }

    var formattedByteCount: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(byteCount),
            countStyle: .file
        )
    }

    var formattedPixelSize: String {
        "\(pixelSize.width) × \(pixelSize.height) px"
    }

    var formattedFormat: String {
        switch format {
        case .jpeg:
            "JPEG"
        case .png:
            "PNG"
        case .heif:
            "HEIC / HEIF"
        case .unknown:
            "Unknown"
        }
    }

    @concurrent
    nonisolated static func prepareSource(_ data: Data) async throws -> Content {
        let reader = try ImageReader(data)
        return try content(
            data: data,
            format: reader.descriptor.format,
            pixelSize: reader.descriptor.orientedPixelSize,
            reader: reader
        )
    }

    @concurrent
    nonisolated static func prepareResult(_ result: WIResult) async throws -> Content {
        try content(
            data: result.data,
            format: result.format,
            pixelSize: result.pixelSize,
            reader: ImageReader(result.data)
        )
    }

    func byteCountChange(comparedTo source: Self) -> ByteCountChange {
        guard byteCount != source.byteCount else {
            return .unchanged
        }

        let change = abs(1 - Double(byteCount) / Double(source.byteCount)) * 100
        return byteCount < source.byteCount
            ? .smaller(percentage: change)
            : .larger(percentage: change)
    }

    init(_ content: Content) {
        self.data = content.data
        self.preview = UIImage(cgImage: content.preview)
        self.format = content.format
        self.pixelSize = content.pixelSize
    }

    nonisolated private static func content(
        data: Data,
        format: ImageFormat,
        pixelSize: WIPixelSize,
        reader: ImageReader
    ) throws -> Content {
        let frame = try reader.thumbnail(
            options: ImageThumbnailOptions(maximumPixelSize: 1_200)
        )

        return Content(
            data: data,
            preview: frame.image,
            format: format,
            pixelSize: pixelSize
        )
    }
}
