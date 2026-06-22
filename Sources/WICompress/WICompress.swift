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
        let writePlan = try WIWritePlanResolver.resolve(options: options, info: imageSource.info)
        let encodedData = try WIImageEncoder.encode(imageSource, plan: writePlan)

        if writePlan.path != .returnOriginal,
           encodedData.count >= data.count,
           WIWritePlanResolver.canReturnOriginalForSizeGuard(options: options, info: imageSource.info) {
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
}
