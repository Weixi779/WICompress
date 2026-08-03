//
//  generate-doc-assets.swift
//  WICompressDocAssetGenerator
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WICompress

private let canvasWidth = 1_600
private let headerHeight = 176
private let rowHeight = 310
private let cardHeight = 268
private let bottomPadding = 72

private struct Sample {
    let title: String
    let filename: String
    let note: String
    let compression: SampleCompression
}

private enum SampleCompression {
    case process(WIImageProcess)
    case target(WICompressionTarget)
}

private struct ImageSummary {
    let thumbnail: CGImage
    let thumbnailData: Data
    let thumbnailMediaType: String
    let format: String
    let displaySize: CGSize
}

private struct RenderedSample {
    let sample: Sample
    let inputData: Data
    let outputData: Data
    let original: ImageSummary
    let compressed: ImageSummary
}

private enum AssetTheme: CaseIterable {
    case light
    case dark

    var filename: String {
        switch self {
        case .light:
            return "compression-comparison-light.svg"
        case .dark:
            return "compression-comparison-dark.svg"
        }
    }

    var palette: Palette {
        switch self {
        case .light:
            return Palette(
                background: "#F6F8FA",
                card: "#FFFFFF",
                border: "#D0D7DE",
                primaryText: "#1F2328",
                secondaryText: "#59636E",
                accent: "#1A7F37",
                checkerLight: "#EAEEF2",
                checkerDark: "#D8DEE4",
                checkerBorder: "#AFB8C1"
            )
        case .dark:
            return Palette(
                background: "#0D1117",
                card: "#161B22",
                border: "#30363D",
                primaryText: "#F0F6FC",
                secondaryText: "#8B949E",
                accent: "#3FB950",
                checkerLight: "#21262D",
                checkerDark: "#30363D",
                checkerBorder: "#484F58"
            )
        }
    }
}

private struct Palette {
    let background: String
    let card: String
    let border: String
    let primaryText: String
    let secondaryText: String
    let accent: String
    let checkerLight: String
    let checkerDark: String
    let checkerBorder: String
}

@main
private enum GenerateDocAssets {
    static func main() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixtureURL = rootURL.appendingPathComponent("Tests/WICompressTests/Resources")
        let outputDirectory = rootURL.appendingPathComponent("docs/assets")

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let renderedSamples = try samples.map { sample in
            try render(sample, fixtureURL: fixtureURL)
        }

        for theme in AssetTheme.allCases {
            let outputURL = outputDirectory.appendingPathComponent(theme.filename)
            let document = svgDocument(for: renderedSamples, theme: theme)
            try document.write(to: outputURL, atomically: true, encoding: .utf8)
            print("Generated \(outputURL.path)")
        }
    }

    private static var samples: [Sample] {
        get throws {
            [
                Sample(
                    title: "HEIC photo - flowers",
                    filename: "real_heic_4032x3024_o6_gps_hdr.heic",
                    note: "Luban 2 keeps HEIC and preserves the display result",
                    compression: .process(lubanV2Process())
                ),
                Sample(
                    title: "HEIC -> JPEG (forced format)",
                    filename: "real_heic_4032x3024_o6_gps_hdr.heic",
                    note: "Explicit JPEG output resizes HEIC for endpoints that only accept JPEG",
                    compression: .process(
                        lubanV2Process(
                            output: WIImageOutput(representation: .jpeg())
                        )
                    )
                ),
                Sample(
                    title: "HEIC photo - large landscape",
                    filename: "real_heic_5712x4284_o6_gps_hdr.heic",
                    note: "Luban 2 resizes and re-encodes a large HEIC photo for upload",
                    compression: .process(lubanV2Process())
                ),
                Sample(
                    title: "HEIC photo - circle cutout",
                    filename: "real_heic_3001x2458_alpha_circle.heic",
                    note: "Transparent HEIC artwork keeps its alpha channel while file size drops",
                    compression: .process(lubanV2Process())
                ),
                Sample(
                    title: "JPEG - landscape photo",
                    filename: "real_jpeg_2098x1350_landscape.jpg",
                    note: "Luban 2 produces the expected upload-size reduction for JPEG",
                    compression: .process(lubanV2Process())
                ),
                Sample(
                    title: "Target API - share thumbnail",
                    filename: "real_jpeg_2098x1350_landscape.jpg",
                    note: "A hard 32 KiB Target solves bytes and square geometry together",
                    compression: .target(
                        try WICompressionTarget(
                            maxBytes: 32 * 1_024,
                            sizing: WICompressionSizing(
                                maximumPixelSize: 200,
                                aspectRatio: .square
                            ),
                            output: WIImageOutput(
                                representation: .jpeg(background: .white),
                                metadata: .strip,
                                colorSpace: .convert(to: .sRGB)
                            )
                        )
                    )
                ),
                Sample(
                    title: "PNG - panoramic screenshot",
                    filename: "real_png_1928x464_pano.png",
                    note: "Luban 2 keeps this ordinary panorama at full resolution",
                    compression: .process(lubanV2Process())
                ),
                Sample(
                    title: "PNG - alpha no-op case",
                    filename: "real_png_1086x1630_alpha.png",
                    note: "Luban 2 keeps the original pixels and the alpha channel remains intact",
                    compression: .process(lubanV2Process())
                ),
            ]
        }
    }

    private static func lubanV2Process(
        output: WIImageOutput = WIImageOutput()
    ) -> WIImageProcess {
        WIImageProcess(
            sizing: .resize(using: WIImageResize.lubanV2),
            output: output
        )
    }

    private static func render(
        _ sample: Sample,
        fixtureURL: URL
    ) throws -> RenderedSample {
        let inputURL = fixtureURL.appendingPathComponent(sample.filename)
        let inputData = try Data(contentsOf: inputURL)
        let outputData: Data
        switch sample.compression {
        case .process(let process):
            outputData = try WICompressor.process(inputData, using: process).data
        case .target(let target):
            outputData = try WICompressor.compress(inputData, to: target).data
        }

        return RenderedSample(
            sample: sample,
            inputData: inputData,
            outputData: outputData,
            original: try summarize(data: inputData, maxPixel: 300),
            compressed: try summarize(data: outputData, maxPixel: 300)
        )
    }
}

private func svgDocument(
    for samples: [RenderedSample],
    theme: AssetTheme
) -> String {
    let palette = theme.palette
    let canvasHeight = headerHeight + samples.count * rowHeight + bottomPadding
    var body: [String] = []

    body.append(text("WICompress 2.0 - Luban 2 Process and Target compression", x: 60, y: 68, style: "headline"))
    body.append(
        text(
            "Generated from real fixtures through WICompressor. Ratio = original bytes ÷ result bytes.",
            x: 60,
            y: 102,
            style: "subtitle"
        )
    )
    body.append(text("Original", x: 740, y: 151, style: "column", anchor: "middle"))
    body.append(text("Compressed", x: 1_195, y: 151, style: "column", anchor: "middle"))

    for (index, renderedSample) in samples.enumerated() {
        let y = headerHeight + index * rowHeight
        body.append(
            "<rect class=\"card\" x=\"40\" y=\"\(y)\" width=\"1520\" height=\"\(cardHeight)\" rx=\"14\"/>"
        )
        body.append(text(renderedSample.sample.title, x: 70, y: y + 54, style: "card-title"))

        for (lineIndex, line) in wrappedLines(renderedSample.sample.note, maximumCharacters: 58).enumerated() {
            body.append(
                text(
                    line,
                    x: 70,
                    y: y + 88 + lineIndex * 20,
                    style: "note"
                )
            )
        }

        let ratio = Double(renderedSample.inputData.count) / max(Double(renderedSample.outputData.count), 1)
        body.append(
            text(
                "Ratio \(String(format: "%.2f", ratio))×",
                x: 70,
                y: y + 154,
                style: "ratio"
            )
        )
        body.append(
            summary(
                renderedSample.original,
                byteCount: renderedSample.inputData.count,
                x: 545,
                y: y + 34,
                identifier: "\(index)-original"
            )
        )
        body.append(
            summary(
                renderedSample.compressed,
                byteCount: renderedSample.outputData.count,
                x: 1_000,
                y: y + 34,
                identifier: "\(index)-compressed"
            )
        )
    }

    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="\(canvasWidth)" height="\(canvasHeight)" viewBox="0 0 \(canvasWidth) \(canvasHeight)" role="img" aria-labelledby="title description">
      <title id="title">WICompress 2.0 compression comparison using Luban 2</title>
      <desc id="description">Real HEIC, JPEG, and PNG fixtures before and after Process or Target compression.</desc>
      <defs>
        <pattern id="checker" width="28" height="28" patternUnits="userSpaceOnUse">
          <rect width="28" height="28" fill="\(palette.checkerLight)"/>
          <path d="M0 0h14v14H0zM14 14h14v14H14z" fill="\(palette.checkerDark)"/>
        </pattern>
      </defs>
      <style>
        .headline { font: 700 30px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: \(palette.primaryText); }
        .subtitle { font: 400 16px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: \(palette.secondaryText); }
        .column { font: 700 18px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: \(palette.primaryText); }
        .card-title { font: 700 20px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: \(palette.primaryText); }
        .note { font: 400 14px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; fill: \(palette.secondaryText); }
        .ratio { font: 700 17px ui-monospace, SFMono-Regular, Menlo, monospace; fill: \(palette.accent); }
        .facts { font: 400 14px ui-monospace, SFMono-Regular, Menlo, monospace; fill: \(palette.secondaryText); }
        .card { fill: \(palette.card); stroke: \(palette.border); stroke-width: 1.5; }
        .preview { fill: url(#checker); stroke: \(palette.checkerBorder); stroke-width: 1; }
      </style>
      <rect width="100%" height="100%" fill="\(palette.background)"/>
      \(body.joined(separator: "\n  "))
    </svg>
    """
}

private func summary(
    _ summary: ImageSummary,
    byteCount: Int,
    x: Int,
    y: Int,
    identifier: String
) -> String {
    let previewWidth = 390
    let previewHeight = 190
    let imageRect = aspectFitRect(
        imageSize: CGSize(width: summary.thumbnail.width, height: summary.thumbnail.height),
        boundingRect: CGRect(x: x, y: y, width: previewWidth, height: previewHeight)
    )
    let dataURI = "data:\(summary.thumbnailMediaType);base64,\(summary.thumbnailData.base64EncodedString())"
    let label = "\(summary.format) · \(formatBytes(byteCount)) · \(Int(summary.displaySize.width))×\(Int(summary.displaySize.height))"

    return """
    <g id="preview-\(identifier)">
      <rect class="preview" x="\(x)" y="\(y)" width="\(previewWidth)" height="\(previewHeight)"/>
      <image href="\(dataURI)" x="\(number(imageRect.minX))" y="\(number(imageRect.minY))" width="\(number(imageRect.width))" height="\(number(imageRect.height))" preserveAspectRatio="xMidYMid meet"/>
      \(text(label, x: x, y: y + 220, style: "facts"))
    </g>
    """
}

private func summarize(data: Data, maxPixel: Int) throws -> ImageSummary {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        throw NSError(domain: "GenerateDocAssets", code: 1)
    }

    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw NSError(domain: "GenerateDocAssets", code: 2)
    }

    let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    let width = intValue(properties[kCGImagePropertyPixelWidth]) ?? thumbnail.width
    let height = intValue(properties[kCGImagePropertyPixelHeight]) ?? thumbnail.height
    let orientation = intValue(properties[kCGImagePropertyOrientation]) ?? 1
    let hasAlpha = boolValue(properties[kCGImagePropertyHasAlpha]) ?? false
    let displaySize = [5, 6, 7, 8].contains(orientation)
        ? CGSize(width: height, height: width)
        : CGSize(width: width, height: height)

    let thumbnailEncoding = try encodedThumbnail(
        thumbnail,
        preservingAlpha: hasAlpha
    )

    return ImageSummary(
        thumbnail: thumbnail,
        thumbnailData: thumbnailEncoding.data,
        thumbnailMediaType: thumbnailEncoding.mediaType,
        format: formatName(forTypeIdentifier: CGImageSourceGetType(source) as String?),
        displaySize: displaySize
    )
}

private func encodedThumbnail(
    _ image: CGImage,
    preservingAlpha: Bool
) throws -> (data: Data, mediaType: String) {
    let type: UTType = preservingAlpha ? .png : .jpeg
    let data = NSMutableData()
    guard
        let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        )
    else {
        throw NSError(domain: "GenerateDocAssets", code: 3)
    }

    let properties: [CFString: Any]? = preservingAlpha
        ? nil
        : [kCGImageDestinationLossyCompressionQuality: 0.86]
    CGImageDestinationAddImage(
        destination,
        image,
        properties.map { $0 as CFDictionary }
    )
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "GenerateDocAssets", code: 4)
    }
    return (
        data: data as Data,
        mediaType: preservingAlpha ? "image/png" : "image/jpeg"
    )
}

private func text(
    _ value: String,
    x: Int,
    y: Int,
    style: String,
    anchor: String = "start"
) -> String {
    "<text class=\"\(style)\" x=\"\(x)\" y=\"\(y)\" text-anchor=\"\(anchor)\">\(xmlEscaped(value))</text>"
}

private func wrappedLines(
    _ value: String,
    maximumCharacters: Int
) -> [String] {
    var lines: [String] = []
    var line = ""

    for word in value.split(separator: " ").map(String.init) {
        let candidate = line.isEmpty ? word : "\(line) \(word)"
        if candidate.count <= maximumCharacters {
            line = candidate
        } else {
            if !line.isEmpty {
                lines.append(line)
            }
            line = word
        }
    }
    if !line.isEmpty {
        lines.append(line)
    }
    return Array(lines.prefix(3))
}

private func aspectFitRect(
    imageSize: CGSize,
    boundingRect: CGRect
) -> CGRect {
    let scale = min(
        boundingRect.width / imageSize.width,
        boundingRect.height / imageSize.height
    )
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return CGRect(
        x: boundingRect.midX - width / 2,
        y: boundingRect.midY - height / 2,
        width: width,
        height: height
    )
}

private func number(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}

private func xmlEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

private func formatBytes(_ byteCount: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(byteCount))
}

private func formatName(forTypeIdentifier typeIdentifier: String?) -> String {
    guard let typeIdentifier, let type = UTType(typeIdentifier) else {
        return "Unknown"
    }
    if type.conforms(to: .jpeg) {
        return "JPEG"
    }
    if type.conforms(to: .png) {
        return "PNG"
    }
    if type.conforms(to: .heic) || type.conforms(to: .heif) {
        return "HEIC"
    }
    return "Unknown"
}

private func intValue(_ value: Any?) -> Int? {
    switch value {
    case let value as Int:
        return value
    case let value as NSNumber:
        return value.intValue
    default:
        return nil
    }
}

private func boolValue(_ value: Any?) -> Bool? {
    switch value {
    case let value as Bool:
        return value
    case let value as NSNumber:
        return value.boolValue
    default:
        return nil
    }
}
