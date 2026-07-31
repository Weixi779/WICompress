//
//  WICompressor.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

@_exported public import WIImageDomain
@_exported public import WICompressExecution

import Foundation

/// ImageIO-backed image processing and compression entry point.
public enum WICompressor {

    /// Processes image data according to one immutable Process description.
    public static func process(
        _ data: Data,
        using process: WIImageProcess = .default
    ) throws(WICompressError) -> WIResult {
        try ImagePipeline.process(data, using: process)
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

    /// Compresses image data to satisfy a target contract.
    public static func compress(
        _ data: Data,
        to target: WICompressionTarget
    ) throws(WICompressError) -> WIResult {
        try ImagePipeline.compress(data, to: target)
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
}
