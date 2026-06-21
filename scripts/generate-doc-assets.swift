import CoreGraphics
import CoreText
import Foundation
import ImageIO
import WICompress

private let canvasWidth = 1600
private let headerHeight = 176
private let rowHeight = 310
private let cardHeight = 268
private let bottomPadding = 116

struct Sample {
    let title: String
    let filename: String
    let note: String
    let options: WICompressOptions
}

struct ImageSummary {
    let data: Data
    let thumbnail: CGImage
    let format: String
    let displaySize: CGSize
}

struct RenderedSample {
    let sample: Sample
    let inputData: Data
    let outputData: Data
    let original: ImageSummary
    let compressed: ImageSummary
}

@main
enum GenerateDocAssets {
    static func main() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixtureURL = rootURL.appendingPathComponent("Tests/WICompressTests/Resources")
        let outputURL = rootURL.appendingPathComponent("docs/assets/compression-comparison.png")

        let samples = [
            Sample(
                title: "HEIC photo - flowers",
                filename: "real_heic_4032x3024_o6_gps_hdr.heic",
                note: "Default compression keeps HEIC and preserves the display result",
                options: .default
            ),
            Sample(
                title: "HEIC photo - large landscape",
                filename: "real_heic_5712x4284_o6_gps_hdr.heic",
                note: "Large HEIC photos get resized and re-encoded for upload",
                options: .default
            ),
            Sample(
                title: "HEIC photo - circle cutout",
                filename: "real_heic_3001x2458_alpha_circle.heic",
                note: "Transparent HEIC artwork stays clean while file size drops",
                options: .default
            ),
            Sample(
                title: "JPEG - landscape photo",
                filename: "real_jpeg_2098x1350_landscape.jpg",
                note: "JPEG gets the expected upload-style size reduction",
                options: .default
            ),
            Sample(
                title: "PNG - panoramic screenshot",
                filename: "real_png_1928x464_pano.png",
                note: "Long PNG keeps full resolution - Luban sizes by the short side, so long images are not over-shrunk",
                options: .default
            ),
            Sample(
                title: "PNG - alpha no-op case",
                filename: "real_png_1086x1630_alpha.png",
                note: "This PNG does not need resize; size guard returns original and alpha remains",
                options: .default
            ),
        ]
        let canvasHeight = headerHeight + samples.count * rowHeight + bottomPadding

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let renderedSamples = try samples.map { sample in
            let inputURL = fixtureURL.appendingPathComponent(sample.filename)
            let inputData = try Data(contentsOf: inputURL)
            let outputData = try WICompress.compress(inputData, options: sample.options)
            return RenderedSample(
                sample: sample,
                inputData: inputData,
                outputData: outputData,
                original: try summarize(data: inputData, maxPixel: 360),
                compressed: try summarize(data: outputData, maxPixel: 360)
            )
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Failed to create bitmap context")
        }

        context.setFillColor(CGColor(gray: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        drawText(
            "WICompress v1.0.0 - Data API compression comparison",
            in: topRect(x: 60, y: 38, width: 1480, height: 44, canvasHeight: canvasHeight),
            fontName: "HelveticaNeue-Bold",
            size: 30,
            color: CGColor(gray: 0.08, alpha: 1),
            context: context
        )
        drawText(
            "Generated from repository fixtures with the default WICompress.compress(_:) API.",
            in: topRect(x: 60, y: 82, width: 1480, height: 24, canvasHeight: canvasHeight),
            fontName: "HelveticaNeue",
            size: 16,
            color: CGColor(gray: 0.34, alpha: 1),
            context: context
        )
        drawText(
            "Original",
            in: topRect(x: 610, y: 132, width: 340, height: 26, canvasHeight: canvasHeight),
            fontName: "HelveticaNeue-Bold",
            size: 18,
            color: CGColor(gray: 0.18, alpha: 1),
            context: context
        )
        drawText(
            "Compressed",
            in: topRect(x: 1060, y: 132, width: 360, height: 26, canvasHeight: canvasHeight),
            fontName: "HelveticaNeue-Bold",
            size: 18,
            color: CGColor(gray: 0.18, alpha: 1),
            context: context
        )

        for (index, renderedSample) in renderedSamples.enumerated() {
            let sample = renderedSample.sample
            let y = CGFloat(headerHeight + index * rowHeight)
            drawCardBackground(
                in: topRect(x: 40, y: y, width: 1520, height: CGFloat(cardHeight), canvasHeight: canvasHeight),
                context: context
            )

            drawText(
                sample.title,
                in: topRect(x: 70, y: y + 30, width: 450, height: 28, canvasHeight: canvasHeight),
                fontName: "HelveticaNeue-Bold",
                size: 20,
                color: CGColor(gray: 0.08, alpha: 1),
                context: context
            )
            drawText(
                sample.note,
                in: topRect(x: 70, y: y + 66, width: 420, height: 48, canvasHeight: canvasHeight),
                fontName: "HelveticaNeue",
                size: 14,
                color: CGColor(gray: 0.34, alpha: 1),
                context: context
            )

            let ratio = Double(renderedSample.inputData.count) / max(Double(renderedSample.outputData.count), 1)
            drawText(
                "Ratio \(String(format: "%.2f", ratio))x",
                in: topRect(x: 70, y: y + 126, width: 200, height: 24, canvasHeight: canvasHeight),
                fontName: "Menlo-Bold",
                size: 17,
                color: CGColor(red: 0.10, green: 0.35, blue: 0.22, alpha: 1),
                context: context
            )

            drawSummary(
                renderedSample.original,
                data: renderedSample.inputData,
                in: topRect(x: 545, y: y + 34, width: 390, height: 200, canvasHeight: canvasHeight),
                context: context
            )
            drawSummary(
                renderedSample.compressed,
                data: renderedSample.outputData,
                in: topRect(x: 1000, y: y + 34, width: 390, height: 200, canvasHeight: canvasHeight),
                context: context
            )
        }

        guard
            let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil)
        else {
            fatalError("Failed to create output image")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Failed to write output image")
        }

        print("Generated \(outputURL.path)")
    }
}

func summarize(data: Data, maxPixel: Int) throws -> ImageSummary {
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
    let displaySize: CGSize
    if [5, 6, 7, 8].contains(orientation) {
        displaySize = CGSize(width: height, height: width)
    } else {
        displaySize = CGSize(width: width, height: height)
    }

    return ImageSummary(
        data: data,
        thumbnail: thumbnail,
        format: formatName(for: WIImageFormat(data: data)),
        displaySize: displaySize
    )
}

func topRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, canvasHeight: Int) -> CGRect {
    CGRect(x: x, y: CGFloat(canvasHeight) - y - height, width: width, height: height)
}

func drawCardBackground(in rect: CGRect, context: CGContext) {
    let path = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.addPath(path)
    context.fillPath()
    context.setStrokeColor(CGColor(gray: 0.87, alpha: 1))
    context.setLineWidth(1)
    context.addPath(path)
    context.strokePath()
}

func drawSummary(_ summary: ImageSummary, data: Data, in rect: CGRect, context: CGContext) {
    drawCheckerboard(in: rect, context: context)
    let imageRect = aspectFitRect(
        imageSize: CGSize(width: summary.thumbnail.width, height: summary.thumbnail.height),
        boundingRect: rect
    )
    context.interpolationQuality = .high
    context.draw(summary.thumbnail, in: imageRect)

    let label = "\(summary.format) - \(formatBytes(data.count)) - \(Int(summary.displaySize.width))x\(Int(summary.displaySize.height))"
    drawText(
        label,
        in: CGRect(x: rect.minX, y: rect.minY - 36, width: rect.width, height: 24),
        fontName: "Menlo",
        size: 14,
        color: CGColor(gray: 0.24, alpha: 1),
        context: context
    )
}

func drawCheckerboard(in rect: CGRect, context: CGContext) {
    context.setFillColor(CGColor(gray: 0.92, alpha: 1))
    context.fill(rect)

    let tile: CGFloat = 14
    context.setFillColor(CGColor(gray: 0.82, alpha: 1))
    var row = 0
    var y = rect.minY
    while y < rect.maxY {
        var column = 0
        var x = rect.minX
        while x < rect.maxX {
            if (row + column).isMultiple(of: 2) {
                context.fill(CGRect(x: x, y: y, width: tile, height: tile))
            }
            x += tile
            column += 1
        }
        y += tile
        row += 1
    }

    context.setStrokeColor(CGColor(gray: 0.78, alpha: 1))
    context.setLineWidth(1)
    context.stroke(rect)
}

func drawText(
    _ text: String,
    in rect: CGRect,
    fontName: String,
    size: CGFloat,
    color: CGColor,
    context: CGContext
) {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
    ]
    let attributedString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
    let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, text.count), path, nil)
    CTFrameDraw(frame, context)
}

func aspectFitRect(imageSize: CGSize, boundingRect: CGRect) -> CGRect {
    let scale = min(boundingRect.width / imageSize.width, boundingRect.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return CGRect(
        x: boundingRect.midX - width / 2,
        y: boundingRect.midY - height / 2,
        width: width,
        height: height
    )
}

func formatBytes(_ byteCount: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(byteCount))
}

func formatName(for format: WIImageFormat) -> String {
    switch format {
    case .jpeg:
        return "JPEG"
    case .png:
        return "PNG"
    case .heif:
        return "HEIC"
    case .unknown:
        return "Unknown"
    }
}

func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
        return value
    }
    if let value = value as? NSNumber {
        return value.intValue
    }
    return nil
}
