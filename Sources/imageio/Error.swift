//
//  Error.swift
//  WIImageIO
//
//  Created by weixi on 2026/8/1.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import UniformTypeIdentifiers

extension WIImageIO {
    /// Failures produced by ImageIO inspection, decoding, copying, and encoding.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The file URL could not be read.
        case fileReadFailed(URL)
        /// The input does not contain a readable image source.
        case invalidImageData
        /// Required image facts could not be inspected.
        case imageInfoUnavailable
        /// Multi-frame image data is not supported by static operations.
        case animatedSourceUnsupported(frameCount: Int)
        /// Source pixels could not be decoded.
        case imageDecodeFailed
        /// The requested metadata cannot be preserved by a source-copy operation.
        case metadataCopyUnsupported(UTType)
        /// Image data could not be encoded as the requested type.
        case imageEncodeFailed(UTType)
    }
}

extension WIImageIO.Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileReadFailed(let url):
            return "Failed to read image data from \(url.path)."
        case .invalidImageData:
            return "The input data is not a readable image source."
        case .imageInfoUnavailable:
            return "Could not inspect the image's basic properties."
        case .animatedSourceUnsupported(let frameCount):
            return "Static ImageIO operations do not support \(frameCount) frames."
        case .imageDecodeFailed:
            return "Could not decode source pixels."
        case .metadataCopyUnsupported(let type):
            return "The requested metadata cannot be preserved while copying as \(type.identifier)."
        case .imageEncodeFailed(let type):
            return "Could not encode image data as \(type.identifier)."
        }
    }
}
