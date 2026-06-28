//
//  WICompress.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// ImageIO-backed image compression entry point.
public struct WICompress: Sendable {

    /// Compresses image data according to the supplied options.
    public static func compress(
        _ data: Data,
        options: WICompressOptions = .default
    ) throws(WICompressError) -> Data {
        let imageSource = try WIImageSource(data: data)
        let sourceColorSpace = try imageSource.colorSpaceInfoIfNeeded(for: options.colorSpace)
        let writePlan = try WIWritePlanResolver.resolve(
            options: options,
            info: imageSource.info,
            sourceColorSpace: sourceColorSpace
        )
        let encodedData = try WIImageEncoder.encode(imageSource, plan: writePlan)

        if writePlan.path != .returnOriginal,
           encodedData.count >= data.count,
           WIWritePlanResolver.canReturnOriginalForSizeGuard(
                options: options,
                info: imageSource.info,
                sourceColorSpace: sourceColorSpace
           ) {
            // Never trade policy correctness for bytes saved.
            return data
        }

        return encodedData
    }

    /// Reads and compresses image data from a file URL.
    public static func compress(
        contentsOf url: URL,
        options: WICompressOptions = .default
    ) throws(WICompressError) -> Data {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw WICompressError.fileReadFailed(url)
        }

        return try compress(data, options: options)
    }

    /// Compresses image data to satisfy a target contract.
    public static func compress(
        _ data: Data,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WICompressionResult {
        try WICompressionTargetResolver.validate(target)

        let imageSource = try WIImageSource(data: data)
        try WICompressionTargetResolver.validate(target, info: imageSource.info)

        let sourceColorSpace = try imageSource.colorSpaceInfoIfNeeded(for: target.output.colorSpace)
        if canReturnOriginal(data, target: target, imageSource: imageSource, sourceColorSpace: sourceColorSpace) {
            return compressionResult(for: data, info: imageSource.info)
        }

        let outputData = try WICompressionSolver.compress(
            imageSource,
            to: target,
            sourceColorSpace: sourceColorSpace
        )
        guard outputData.count <= target.maxBytes else {
            throw WICompressError.targetUnsatisfiable(smallestByteCount: outputData.count)
        }

        return try compressionResult(for: outputData)
    }

    /// Reads image data from a file URL and compresses it to satisfy a target contract.
    public static func compress(
        contentsOf url: URL,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WICompressionResult {
        try WICompressionTargetResolver.validate(target)

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw WICompressError.fileReadFailed(url)
        }

        return try compress(data, to: target)
    }

    private static func canReturnOriginal(
        _ data: Data,
        target: WICompressionTarget,
        imageSource: WIImageSource,
        sourceColorSpace: WISourceColorSpaceInfo?
    ) -> Bool {
        guard data.count <= target.maxBytes,
              let options = try? WICompressionTargetResolver.options(for: target) else {
            return false
        }

        return WIWritePlanResolver.canReturnOriginalForSizeGuard(
            options: options,
            info: imageSource.info,
            sourceColorSpace: sourceColorSpace
        )
    }

    private static func compressionResult(for data: Data) throws(WICompressError) -> WICompressionResult {
        let imageSource = try WIImageSource(data: data)
        guard imageSource.info.sourceFormat != .unknown else {
            throw WICompressError.unsupportedSourceFormat(imageSource.info.typeIdentifier)
        }

        return compressionResult(for: data, info: imageSource.info)
    }

    private static func compressionResult(for data: Data, info: WIImageInfo) -> WICompressionResult {
        WICompressionResult(
            data: data,
            format: info.sourceFormat,
            pixelSize: info.displaySize,
            byteCount: data.count
        )
    }
}
