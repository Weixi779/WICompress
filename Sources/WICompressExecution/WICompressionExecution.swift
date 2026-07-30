//
//  WICompressionExecution.swift
//  WICompressExecution
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain
import WIImageIO

/// ImageIO-backed image processing and compression entry point.
package enum WICompressionExecution {

    /// Processes image data according to one immutable Process description.
    package static func process(
        _ data: Data,
        using process: WIImageProcess = .default
    ) throws(WICompressError) -> WIResult {
        let imageSource = try WIImageSource(data: data)
        return try self.process(imageSource, using: process)
    }

    /// Reads and processes image data from a file URL.
    package static func process(
        contentsOf url: URL,
        using process: WIImageProcess = .default
    ) throws(WICompressError) -> WIResult {
        let imageSource = try WIImageSource(contentsOf: url)
        return try self.process(imageSource, using: process)
    }

    private static func process(
        _ imageSource: WIImageSource,
        using process: WIImageProcess
    ) throws(WICompressError) -> WIResult {
        let executionPlan = try WIImageProcessResolver.resolve(
            process,
            imageSource: imageSource
        )
        let outputData = try WIImageExecutor.execute(
            imageSource,
            plan: executionPlan
        )
        return try compressionResult(for: outputData)
    }

    /// Compresses image data to satisfy a target contract.
    package static func compress(
        _ data: Data,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try WICompressionTargetValidator.validate(target)

        let imageSource = try WIImageSource(data: data)
        return try compress(imageSource, to: target)
    }

    /// Reads image data from a file URL and compresses it to satisfy a target contract.
    package static func compress(
        contentsOf url: URL,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try WICompressionTargetValidator.validate(target)

        let imageSource = try WIImageSource(contentsOf: url)
        return try compress(imageSource, to: target)
    }

    private static func compress(
        _ imageSource: WIImageSource,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
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
                descriptor: imageSource.descriptor
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

    private static func compressionResult(
        for data: Data
    ) throws(WICompressError) -> WIResult {
        let imageSource = try WIImageSource(data: data)
        guard imageSource.descriptor.format != .unknown else {
            throw WICompressError.unsupportedSourceFormat(
                imageSource.descriptor.typeIdentifier
            )
        }

        return compressionResult(
            for: data,
            descriptor: imageSource.descriptor
        )
    }

    private static func compressionResult(
        for data: Data,
        descriptor: WIImageIO.Descriptor
    ) -> WIResult {
        WIResult(
            data: data,
            format: descriptor.format,
            pixelSize: descriptor.orientedPixelSize
        )
    }
}
