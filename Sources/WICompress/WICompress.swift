//
//  WICompress.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageCore

/// ImageIO-backed image compression entry point.
public struct WICompress: Sendable {

    /// Processes image data according to one immutable Process description.
    public static func process(
        _ data: Data,
        using process: WIImageProcess = .default
    ) throws(WICompressError) -> Data {
        let imageSource = try WIImageSource(data: data)
        return try self.process(imageSource, using: process)
    }

    /// Reads and processes image data from a file URL.
    public static func process(
        contentsOf url: URL,
        using process: WIImageProcess = .default
    ) throws(WICompressError) -> Data {
        let imageSource = try WIImageSource(contentsOf: url)
        return try self.process(imageSource, using: process)
    }

    private static func process(
        _ imageSource: WIImageSource,
        using process: WIImageProcess
    ) throws(WICompressError) -> Data {
        let executionPlan = try WIImageProcessResolver.resolve(
            process,
            imageSource: imageSource
        )
        return try WIImageEncoder.encode(
            imageSource,
            plan: executionPlan
        )
    }

    /// Compresses image data to satisfy a target contract.
    public static func compress(
        _ data: Data,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WICompressionResult {
        try WICompressionTargetValidator.validate(target)

        let imageSource = try WIImageSource(data: data)
        return try compress(imageSource, to: target)
    }

    /// Reads image data from a file URL and compresses it to satisfy a target contract.
    public static func compress(
        contentsOf url: URL,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WICompressionResult {
        try WICompressionTargetValidator.validate(target)

        let imageSource = try WIImageSource(contentsOf: url)
        return try compress(imageSource, to: target)
    }

    private static func compress(
        _ imageSource: WIImageSource,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WICompressionResult {
        let sizing = try WICompressionTargetResolver.sizing(
            for: target,
            imageSource: imageSource
        )
        let output = try WICompressionTargetResolver.output(
            for: target,
            imageSource: imageSource
        )
        if WICompressionTargetResolver.canReturnOriginal(
            target: target,
            sizing: sizing,
            output: output,
            imageSource: imageSource
        ) {
            let data = try imageSource.originalData()
            return compressionResult(
                for: data,
                info: imageSource.info
            )
        }

        let outputData = try WICompressionSolver.compress(
            imageSource,
            to: target,
            sizing: sizing,
            output: output
        )
        guard outputData.count <= target.maxBytes else {
            throw WICompressError.targetUnsatisfiable(
                smallestByteCount: outputData.count
            )
        }

        return try compressionResult(for: outputData)
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
            format: WIImageFormat(info.sourceFormat),
            pixelSize: info.displaySize,
            byteCount: data.count
        )
    }
}
