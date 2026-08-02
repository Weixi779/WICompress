//
//  WICompressor.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

@_exported public import WIImageDomain
@_exported public import WICompressDomain

import Foundation
import WICompressExecution

/// ImageIO-backed image processing and compression entry point.
public enum WICompressor {

    /// Processes image data according to one immutable Process description.
    public static func process(
        _ data: Data,
        using process: WIImageProcess = .default
    ) throws(WICompressError) -> WIResult {
        try ImagePipeline.process(data, using: process)
    }

    /// Processes image data without occupying the caller's actor.
    ///
    /// Cancellation is observed between processing stages. An in-flight ImageIO or Core Graphics
    /// operation may finish before cancellation takes effect.
    ///
    /// - Throws: `CancellationError` if the surrounding task is cancelled, or `WICompressError`
    ///   when image processing fails.
    @concurrent
    public static func process(
        _ data: Data,
        using process: WIImageProcess = .default
    ) async throws -> WIResult {
        try ImagePipeline.processCancellable(data, using: process)
    }

    /// Reads and processes image data from a file URL.
    public static func process(
        contentsOf url: URL,
        using process: WIImageProcess = .default
    ) throws(WICompressError) -> WIResult {
        try ImagePipeline.process(
            contentsOf: url,
            using: process
        )
    }

    /// Reads and processes image data from a file URL without occupying the caller's actor.
    ///
    /// Cancellation is observed between processing stages. An in-flight ImageIO or Core Graphics
    /// operation may finish before cancellation takes effect.
    ///
    /// - Throws: `CancellationError` if the surrounding task is cancelled, or `WICompressError`
    ///   when reading or processing the image fails.
    @concurrent
    public static func process(
        contentsOf url: URL,
        using process: WIImageProcess = .default
    ) async throws -> WIResult {
        try ImagePipeline.processCancellable(
            contentsOf: url,
            using: process
        )
    }

    /// Compresses image data to satisfy a target contract.
    public static func compress(
        _ data: Data,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try ImagePipeline.compress(data, to: target)
    }

    /// Compresses image data to a target contract without occupying the caller's actor.
    ///
    /// Cancellation is observed between search attempts and processing stages. An in-flight
    /// ImageIO or Core Graphics operation may finish before cancellation takes effect.
    ///
    /// - Throws: `CancellationError` if the surrounding task is cancelled, or `WICompressError`
    ///   when target compression fails.
    @concurrent
    public static func compress(
        _ data: Data,
        to target: WICompressionTarget
    ) async throws -> WIResult {
        try ImagePipeline.compressCancellable(data, to: target)
    }

    /// Reads image data from a file URL and compresses it to satisfy a target contract.
    public static func compress(
        contentsOf url: URL,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try ImagePipeline.compress(
            contentsOf: url,
            to: target
        )
    }

    /// Reads image data from a file URL and compresses it without occupying the caller's actor.
    ///
    /// Cancellation is observed between search attempts and processing stages. An in-flight
    /// ImageIO or Core Graphics operation may finish before cancellation takes effect.
    ///
    /// - Throws: `CancellationError` if the surrounding task is cancelled, or `WICompressError`
    ///   when reading or compressing the image fails.
    @concurrent
    public static func compress(
        contentsOf url: URL,
        to target: WICompressionTarget
    ) async throws -> WIResult {
        try ImagePipeline.compressCancellable(
            contentsOf: url,
            to: target
        )
    }
}
