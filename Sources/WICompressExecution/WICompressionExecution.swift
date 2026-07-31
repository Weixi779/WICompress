//
//  WICompressionExecution.swift
//  WICompressExecution
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WIImageDomain

/// ImageIO-backed image processing and compression entry point.
package enum WICompressionExecution {

    /// Processes image data according to one immutable Process description.
    package static func process(
        _ data: Data,
        using process: WIImageProcess = .default
    ) throws(WICompressError) -> WIResult {
        let pipeline = try ImagePipeline(data: data)
        return try self.process(pipeline, using: process)
    }

    /// Reads and processes image data from a file URL.
    package static func process(
        contentsOf url: URL,
        using process: WIImageProcess = .default
    ) throws(WICompressError) -> WIResult {
        let pipeline = try ImagePipeline(contentsOf: url)
        return try self.process(pipeline, using: process)
    }

    private static func process(
        _ pipeline: ImagePipeline,
        using process: WIImageProcess
    ) throws(WICompressError) -> WIResult {
        try pipeline.process(process)
    }

    /// Compresses image data to satisfy a target contract.
    package static func compress(
        _ data: Data,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try WICompressionTargetValidator.validate(target)

        let pipeline = try ImagePipeline(data: data)
        return try compress(pipeline, to: target)
    }

    /// Reads image data from a file URL and compresses it to satisfy a target contract.
    package static func compress(
        contentsOf url: URL,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try WICompressionTargetValidator.validate(target)

        let pipeline = try ImagePipeline(contentsOf: url)
        return try compress(pipeline, to: target)
    }

    private static func compress(
        _ pipeline: ImagePipeline,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        let sizing = try WICompressionTargetResolver.sizing(
            for: target,
            pipeline: pipeline
        )
        let output = try WICompressionTargetResolver.output(
            for: target,
            pipeline: pipeline
        )
        if WICompressionTargetResolver.canReturnOriginal(
            target: target,
            sizing: sizing,
            output: output,
            pipeline: pipeline
        ) {
            return try pipeline.originalResult()
        }

        let outputData = try WICompressionSolver.compress(
            pipeline,
            to: target,
            sizing: sizing,
            output: output
        )
        guard outputData.count <= target.maxBytes else {
            throw WICompressError.targetUnsatisfiable(
                smallestByteCount: outputData.count
            )
        }

        return try pipeline.result(for: outputData)
    }
}
