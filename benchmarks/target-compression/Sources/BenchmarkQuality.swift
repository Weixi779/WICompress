//
//  BenchmarkQuality.swift
//  TargetCompressionBenchmark
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Accelerate
import CoreGraphics
import Foundation
import WIImageIO

struct BenchmarkQualityReport: Codable, Equatable, Sendable {
    let protocolID: String
    let mseRGB: Double?
    let psnrRGBDB: Double?
    let ssimLuma: Double?
    let exactMatch: Bool
    let unavailableReason: BenchmarkQualityUnavailableReason?
    let referenceWidth: Int
    let referenceHeight: Int
}

enum BenchmarkQualityUnavailableReason: String, Codable, Sendable {
    case sourceContainsTransparency
    case outputContainsTransparency
    case sourceAndOutputContainTransparency
}

enum BenchmarkQualityError: String, Codable, Error, LocalizedError, Sendable {
    case decodedPixelBufferLimitExceeded
    case ssimWorkspaceLimitExceeded
    case invalidPixelBufferSize
    case imageConversionFailed
    case imageScaleFailed
    case inconsistentPixelDimensions

    var errorDescription: String? {
        switch self {
        case .decodedPixelBufferLimitExceeded:
            return "Quality measurement exceeded the 256 MiB limit for one decoded pixel buffer."
        case .ssimWorkspaceLimitExceeded:
            return "Quality measurement exceeded the 256 MiB SSIM workspace limit."
        case .invalidPixelBufferSize:
            return "Quality measurement requires executable pixel dimensions."
        case .imageConversionFailed:
            return "Quality measurement could not convert the image to sRGB8 pixels."
        case .imageScaleFailed:
            return "Quality measurement could not scale the reference image."
        case .inconsistentPixelDimensions:
            return "Quality measurement produced inconsistent reference and output dimensions."
        }
    }
}

enum BenchmarkQualityEvaluator {
    static let protocolID =
        "srgb8-exif-vimage-hq-rgba-alpha-scan-rgb-mse-psnr-bt709-ssim11-sigma1.5-valid-pixelcap256m-ssimcap256m-v2"

    static func evaluate(
        sourceData: Data,
        outputData: Data
    ) throws -> BenchmarkQualityReport {
        let sourcePixels = try normalizedPixels(from: sourceData)
        let outputPixels = try normalizedPixels(from: outputData)
        let sourceContainsTransparency = sourcePixels.hasTransparency
        let outputContainsTransparency = outputPixels.hasTransparency

        if sourceContainsTransparency || outputContainsTransparency {
            let reason: BenchmarkQualityUnavailableReason = switch (
                sourceContainsTransparency,
                outputContainsTransparency
            ) {
            case (true, true):
                .sourceAndOutputContainTransparency
            case (true, false):
                .sourceContainsTransparency
            case (false, true):
                .outputContainsTransparency
            case (false, false):
                preconditionFailure("Alpha unavailability requires an alpha-bearing image.")
            }

            return BenchmarkQualityReport(
                protocolID: protocolID,
                mseRGB: nil,
                psnrRGBDB: nil,
                ssimLuma: nil,
                exactMatch: false,
                unavailableReason: reason,
                referenceWidth: outputPixels.width,
                referenceHeight: outputPixels.height
            )
        }

        let reference = try sourcePixels.scaled(
            width: outputPixels.width,
            height: outputPixels.height
        )

        guard reference.width == outputPixels.width,
            reference.height == outputPixels.height
        else {
            throw BenchmarkQualityError.inconsistentPixelDimensions
        }

        let mseRGB = meanSquaredRGBError(reference: reference, output: outputPixels)
        let exactMatch = mseRGB == 0
        let psnrRGBDB = exactMatch
            ? nil
            : 10 * log10((255 * 255) / mseRGB)

        return BenchmarkQualityReport(
            protocolID: protocolID,
            mseRGB: mseRGB,
            psnrRGBDB: psnrRGBDB,
            ssimLuma: try lumaStructuralSimilarity(reference: reference, output: outputPixels),
            exactMatch: exactMatch,
            unavailableReason: nil,
            referenceWidth: reference.width,
            referenceHeight: reference.height
        )
    }

    private static func normalizedPixels(from data: Data) throws -> PixelBuffer {
        let reader = try ImageReader(data)
        try PixelBuffer.validateDecodedSize(
            width: reader.descriptor.pixelSize.width,
            height: reader.descriptor.pixelSize.height
        )
        let frame = try reader.image()
        return try PixelBuffer(frame: frame).applyingOrientation(frame.orientation)
    }
}

// MARK: - Pixel Normalization

private struct PixelBuffer {
    static let bytesPerPixel = 4
    static let maximumByteCount = 256 * 1024 * 1024

    let data: Data
    let width: Int
    let height: Int
    let rowBytes: Int

    fileprivate static func validateDecodedSize(width: Int, height: Int) throws {
        _ = try byteCount(
            rowBytes: tightRowBytes(width: width),
            height: height
        )
    }

    init(frame: ImageFrame) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw BenchmarkQualityError.imageConversionFailed
        }

        try Self.validateDecodedSize(width: frame.image.width, height: frame.image.height)

        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passUnretained(colorSpace),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder32Big),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )
        var buffer = vImage_Buffer()
        let error = vImageBuffer_InitWithCGImage(
            &buffer,
            &format,
            nil,
            frame.image,
            vImage_Flags(kvImageNoFlags)
        )
        guard error == kvImageNoError, let bytes = buffer.data else {
            if buffer.data != nil {
                free(buffer.data)
            }
            throw BenchmarkQualityError.imageConversionFailed
        }

        guard buffer.width <= Int.max,
            buffer.height <= Int.max,
            buffer.rowBytes <= Int.max
        else {
            free(bytes)
            throw BenchmarkQualityError.invalidPixelBufferSize
        }

        let width = Int(buffer.width)
        let height = Int(buffer.height)
        let rowBytes = Int(buffer.rowBytes)
        let (minimumRowBytes, rowOverflow) = width.multipliedReportingOverflow(
            by: Self.bytesPerPixel
        )
        let (byteCount, overflow) = rowBytes.multipliedReportingOverflow(by: height)
        guard
            width > 0,
            height > 0,
            !rowOverflow,
            rowBytes >= minimumRowBytes,
            !overflow
        else {
            free(bytes)
            throw BenchmarkQualityError.invalidPixelBufferSize
        }
        guard byteCount <= Self.maximumByteCount else {
            free(bytes)
            throw BenchmarkQualityError.decodedPixelBufferLimitExceeded
        }

        self.data = Data(bytesNoCopy: bytes, count: byteCount, deallocator: .free)
        self.width = width
        self.height = height
        self.rowBytes = rowBytes
    }

    init(
        data: Data,
        width: Int,
        height: Int,
        rowBytes: Int
    ) {
        self.data = data
        self.width = width
        self.height = height
        self.rowBytes = rowBytes
    }

    var hasTransparency: Bool {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return true
            }
            for y in 0..<height {
                let row = base.advanced(by: y * rowBytes)
                for x in 0..<width where row[x * Self.bytesPerPixel + 3] != 255 {
                    return true
                }
            }
            return false
        }
    }

    func applyingOrientation(_ orientation: WIImageOrientation) throws -> Self {
        guard orientation != .up else {
            return self
        }

        let outputWidth = orientation.swapsDimensions ? height : width
        let outputHeight = orientation.swapsDimensions ? width : height
        let outputRowBytes = try Self.tightRowBytes(width: outputWidth)
        let outputByteCount = try Self.byteCount(
            rowBytes: outputRowBytes,
            height: outputHeight
        )
        var outputData = Data(count: outputByteCount)

        data.withUnsafeBytes { sourceBytes in
            outputData.withUnsafeMutableBytes { outputBytes in
                guard let source = sourceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    let output = outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else {
                    return
                }

                for outputY in 0..<outputHeight {
                    for outputX in 0..<outputWidth {
                        let sourceCoordinate = sourceCoordinate(
                            outputX: outputX,
                            outputY: outputY,
                            orientation: orientation
                        )
                        let sourceOffset = sourceCoordinate.y * rowBytes
                            + sourceCoordinate.x * Self.bytesPerPixel
                        let outputOffset = outputY * outputRowBytes
                            + outputX * Self.bytesPerPixel
                        output.advanced(by: outputOffset).update(
                            from: source.advanced(by: sourceOffset),
                            count: Self.bytesPerPixel
                        )
                    }
                }
            }
        }

        return Self(
            data: outputData,
            width: outputWidth,
            height: outputHeight,
            rowBytes: outputRowBytes
        )
    }

    func scaled(width outputWidth: Int, height outputHeight: Int) throws -> Self {
        guard width != outputWidth || height != outputHeight else {
            return self
        }

        let outputRowBytes = try Self.tightRowBytes(width: outputWidth)
        let outputByteCount = try Self.byteCount(
            rowBytes: outputRowBytes,
            height: outputHeight
        )
        var outputData = Data(count: outputByteCount)
        let error = data.withUnsafeBytes { sourceBytes in
            outputData.withUnsafeMutableBytes { outputBytes in
                var source = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: sourceBytes.baseAddress),
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: rowBytes
                )
                var output = vImage_Buffer(
                    data: outputBytes.baseAddress,
                    height: vImagePixelCount(outputHeight),
                    width: vImagePixelCount(outputWidth),
                    rowBytes: outputRowBytes
                )
                return vImageScale_ARGB8888(
                    &source,
                    &output,
                    nil,
                    vImage_Flags(kvImageHighQualityResampling)
                )
            }
        }
        guard error == kvImageNoError else {
            throw BenchmarkQualityError.imageScaleFailed
        }

        return Self(
            data: outputData,
            width: outputWidth,
            height: outputHeight,
            rowBytes: outputRowBytes
        )
    }

    private func sourceCoordinate(
        outputX: Int,
        outputY: Int,
        orientation: WIImageOrientation
    ) -> (x: Int, y: Int) {
        switch orientation {
        case .up:
            return (outputX, outputY)
        case .upMirrored:
            return (width - 1 - outputX, outputY)
        case .down:
            return (width - 1 - outputX, height - 1 - outputY)
        case .downMirrored:
            return (outputX, height - 1 - outputY)
        case .leftMirrored:
            return (outputY, outputX)
        case .right:
            return (outputY, height - 1 - outputX)
        case .rightMirrored:
            return (width - 1 - outputY, height - 1 - outputX)
        case .left:
            return (width - 1 - outputY, outputX)
        }
    }

    private static func tightRowBytes(width: Int) throws -> Int {
        let (rowBytes, overflow) = width.multipliedReportingOverflow(by: bytesPerPixel)
        guard width > 0, !overflow else {
            throw BenchmarkQualityError.invalidPixelBufferSize
        }
        return rowBytes
    }

    private static func byteCount(rowBytes: Int, height: Int) throws -> Int {
        let (byteCount, overflow) = rowBytes.multipliedReportingOverflow(by: height)
        guard height > 0, !overflow else {
            throw BenchmarkQualityError.invalidPixelBufferSize
        }
        guard byteCount <= maximumByteCount else {
            throw BenchmarkQualityError.decodedPixelBufferLimitExceeded
        }
        return byteCount
    }
}

// MARK: - RGB Error

private func meanSquaredRGBError(
    reference: PixelBuffer,
    output: PixelBuffer
) -> Double {
    var squaredError = 0.0

    reference.data.withUnsafeBytes { referenceBytes in
        output.data.withUnsafeBytes { outputBytes in
            guard let referenceBase = referenceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let outputBase = outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
            else {
                return
            }

            for y in 0..<reference.height {
                let referenceRow = referenceBase.advanced(by: y * reference.rowBytes)
                let outputRow = outputBase.advanced(by: y * output.rowBytes)
                for x in 0..<reference.width {
                    let pixelOffset = x * PixelBuffer.bytesPerPixel
                    for component in 0..<3 {
                        let difference = Double(referenceRow[pixelOffset + component])
                            - Double(outputRow[pixelOffset + component])
                        squaredError += difference * difference
                    }
                }
            }
        }
    }

    return squaredError / Double(reference.width * reference.height * 3)
}

// MARK: - Structural Similarity

private func lumaStructuralSimilarity(
    reference: PixelBuffer,
    output: PixelBuffer
) throws -> Double? {
    let windowSize = 11
    guard reference.width >= windowSize, reference.height >= windowSize else {
        return nil
    }

    let kernel = gaussianKernel(size: windowSize, sigma: 1.5)
    let validWidth = reference.width - windowSize + 1
    let validHeight = reference.height - windowSize + 1
    var rows = try SSIMRows(
        imageWidth: reference.width,
        validWidth: validWidth,
        windowSize: windowSize
    )
    var scoreSum = 0.0

    reference.data.withUnsafeBytes { referenceBytes in
        output.data.withUnsafeBytes { outputBytes in
            guard let referenceBase = referenceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let outputBase = outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
            else {
                return
            }

            for y in 0..<reference.height {
                rows.readLuma(
                    reference: referenceBase.advanced(by: y * reference.rowBytes),
                    output: outputBase.advanced(by: y * output.rowBytes)
                )
                rows.convolveHorizontally(kernel: kernel, row: y)

                guard y >= windowSize - 1 else {
                    continue
                }
                rows.convolveVertically(kernel: kernel, endingAt: y)
                scoreSum += rows.structuralSimilaritySum()
            }
        }
    }

    return scoreSum / Double(validWidth * validHeight)
}

private func gaussianKernel(size: Int, sigma: Float) -> [Float] {
    let radius = size / 2
    let denominator = 2 * sigma * sigma
    var kernel = (-radius...radius).map { offset in
        exp(-Float(offset * offset) / denominator)
    }
    let sum = kernel.reduce(0, +)
    for index in kernel.indices {
        kernel[index] /= sum
    }
    return kernel
}

private struct SSIMRows {
    private static let statisticCount = 5
    private static let maximumWorkspaceByteCount = 256 * 1024 * 1024

    private let imageWidth: Int
    private let validWidth: Int
    private let windowSize: Int
    private var signals: [Float]
    private var horizontalRing: [Float]
    private var statistics: [Float]

    init(
        imageWidth: Int,
        validWidth: Int,
        windowSize: Int
    ) throws {
        let signalCount = try Self.elementCount(
            Self.statisticCount,
            imageWidth
        )
        let horizontalCount = try Self.elementCount(
            Self.statisticCount,
            windowSize,
            validWidth
        )
        let statisticsCount = try Self.elementCount(
            Self.statisticCount,
            validWidth
        )
        let workspaceElementCount = try Self.sum(
            signalCount,
            horizontalCount,
            statisticsCount
        )
        let workspaceByteCount = try Self.elementCount(
            workspaceElementCount,
            MemoryLayout<Float>.stride
        )
        guard workspaceByteCount <= Self.maximumWorkspaceByteCount else {
            throw BenchmarkQualityError.ssimWorkspaceLimitExceeded
        }

        self.imageWidth = imageWidth
        self.validWidth = validWidth
        self.windowSize = windowSize
        self.signals = [Float](
            repeating: 0,
            count: signalCount
        )
        self.horizontalRing = [Float](
            repeating: 0,
            count: horizontalCount
        )
        self.statistics = [Float](
            repeating: 0,
            count: statisticsCount
        )
    }

    private static func elementCount(_ factors: Int...) throws -> Int {
        try factors.reduce(1) { result, factor in
            guard factor > 0 else {
                throw BenchmarkQualityError.ssimWorkspaceLimitExceeded
            }
            let (product, overflow) = result.multipliedReportingOverflow(by: factor)
            guard !overflow else {
                throw BenchmarkQualityError.ssimWorkspaceLimitExceeded
            }
            return product
        }
    }

    private static func sum(_ values: Int...) throws -> Int {
        try values.reduce(0) { result, value in
            let (sum, overflow) = result.addingReportingOverflow(value)
            guard !overflow else {
                throw BenchmarkQualityError.ssimWorkspaceLimitExceeded
            }
            return sum
        }
    }

    mutating func readLuma(
        reference: UnsafePointer<UInt8>,
        output: UnsafePointer<UInt8>
    ) {
        for x in 0..<imageWidth {
            let pixelOffset = x * PixelBuffer.bytesPerPixel
            let referenceLuma = Self.luma(reference.advanced(by: pixelOffset))
            let outputLuma = Self.luma(output.advanced(by: pixelOffset))

            signals[x] = referenceLuma
            signals[imageWidth + x] = outputLuma
            signals[2 * imageWidth + x] = referenceLuma * referenceLuma
            signals[3 * imageWidth + x] = outputLuma * outputLuma
            signals[4 * imageWidth + x] = referenceLuma * outputLuma
        }
    }

    mutating func convolveHorizontally(kernel: [Float], row: Int) {
        let ringRow = row % windowSize
        signals.withUnsafeBufferPointer { signalBuffer in
            kernel.withUnsafeBufferPointer { kernelBuffer in
                horizontalRing.withUnsafeMutableBufferPointer { ringBuffer in
                    guard let signalBase = signalBuffer.baseAddress,
                        let kernelBase = kernelBuffer.baseAddress,
                        let ringBase = ringBuffer.baseAddress
                    else {
                        return
                    }

                    for statistic in 0..<Self.statisticCount {
                        let signal = signalBase.advanced(by: statistic * imageWidth)
                        let destination = ringBase.advanced(
                            by: (statistic * windowSize + ringRow) * validWidth
                        )
                        vDSP_conv(
                            signal,
                            1,
                            kernelBase,
                            1,
                            destination,
                            1,
                            vDSP_Length(validWidth),
                            vDSP_Length(windowSize)
                        )
                    }
                }
            }
        }
    }

    mutating func convolveVertically(kernel: [Float], endingAt row: Int) {
        statistics.withUnsafeMutableBufferPointer { statisticsBuffer in
            horizontalRing.withUnsafeBufferPointer { ringBuffer in
                kernel.withUnsafeBufferPointer { kernelBuffer in
                    guard let statisticsBase = statisticsBuffer.baseAddress,
                        let ringBase = ringBuffer.baseAddress,
                        let kernelBase = kernelBuffer.baseAddress
                    else {
                        return
                    }

                    vDSP_vclr(
                        statisticsBase,
                        1,
                        vDSP_Length(Self.statisticCount * validWidth)
                    )
                    for statistic in 0..<Self.statisticCount {
                        let destination = statisticsBase.advanced(by: statistic * validWidth)
                        for kernelIndex in 0..<windowSize {
                            let sourceRow = (row - windowSize + 1 + kernelIndex) % windowSize
                            let source = ringBase.advanced(
                                by: (statistic * windowSize + sourceRow) * validWidth
                            )
                            var weight = kernelBase[kernelIndex]
                            vDSP_vsma(
                                source,
                                1,
                                &weight,
                                destination,
                                1,
                                destination,
                                1,
                                vDSP_Length(validWidth)
                            )
                        }
                    }
                }
            }
        }
    }

    func structuralSimilaritySum() -> Double {
        let c1 = Float((0.01 * 255) * (0.01 * 255))
        let c2 = Float((0.03 * 255) * (0.03 * 255))
        var sum = 0.0

        for x in 0..<validWidth {
            let referenceMean = statistics[x]
            let outputMean = statistics[validWidth + x]
            let referenceVariance = max(
                statistics[2 * validWidth + x] - referenceMean * referenceMean,
                0
            )
            let outputVariance = max(
                statistics[3 * validWidth + x] - outputMean * outputMean,
                0
            )
            let covariance = statistics[4 * validWidth + x]
                - referenceMean * outputMean
            let luminance = (2 * referenceMean * outputMean + c1)
                / (referenceMean * referenceMean + outputMean * outputMean + c1)
            let structure = (2 * covariance + c2)
                / (referenceVariance + outputVariance + c2)
            sum += Double(luminance * structure)
        }
        return sum
    }

    private static func luma(_ pixel: UnsafePointer<UInt8>) -> Float {
        0.2126 * Float(pixel[0])
            + 0.7152 * Float(pixel[1])
            + 0.0722 * Float(pixel[2])
    }
}
