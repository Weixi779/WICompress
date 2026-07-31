//
//  WICompressError.swift
//  WIImageDomain
//
//  Created by weixi on 2026/7/31.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Errors thrown while processing or compressing an image.
public enum WICompressError: Swift.Error, Sendable, Equatable {
    // MARK: - Input

    /// The file URL could not be read.
    case fileReadFailed(URL)
    /// The input data is not a decodable image.
    case invalidImageData
    /// Required image facts could not be read.
    case imageInfoUnavailable
    /// The source container is not supported.
    case unsupportedSourceFormat(String?)
    /// Multi-frame image data is not supported.
    case animatedSourceUnsupported(frameCount: Int)

    // MARK: - Request

    /// The requested crop ratio is invalid.
    case invalidCrop
    /// The requested resizing operation is invalid.
    case invalidResizing
    /// The target compression request is not valid.
    case invalidTarget
    /// Transparent source data needs an explicit background before JPEG encoding.
    case transparentSourceRequiresBackground(WIImageFormat)
    /// JPEG background colors must be fully opaque.
    case nonOpaqueJPEGBackground

    // MARK: - Capability

    /// The current platform cannot write the requested destination format.
    case unsupportedDestinationFormat(WIImageFormat)
    /// The requested color space is not available on the current platform.
    case unsupportedColorSpace
    /// The supplied ICC profile could not create a color space.
    case invalidICCProfile

    // MARK: - Processing

    /// Source pixels could not be decoded.
    case imageDecodeFailed
    /// Image pixels could not be rendered as requested.
    case imageRenderingFailed
    /// Image data could not be encoded in the requested format.
    case imageEncodeFailed(WIImageFormat)

    // MARK: - Target Search

    /// The target constraints cannot be satisfied by the supported encoder path.
    case targetUnsatisfiable(smallestByteCount: Int?)
    /// The target search reached its internal resource budget.
    case resourceLimitExceeded(attemptCount: Int)
}

extension WICompressError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileReadFailed(let url):
            return "Failed to read image data from \(url.path)."
        case .invalidImageData:
            return "The input data is not a decodable image."
        case .imageInfoUnavailable:
            return "Could not read basic image information (pixel size, format)."
        case .unsupportedSourceFormat(let identifier):
            return "Unsupported source image format: \(identifier ?? "unknown")."
        case .animatedSourceUnsupported(let frameCount):
            return "Animated images are not supported (\(frameCount) frames)."

        case .invalidCrop:
            return "Image crop ratios must be finite and positive."
        case .invalidResizing:
            return "The requested image resizing operation is invalid."
        case .invalidTarget:
            return "The compression target is invalid."
        case .transparentSourceRequiresBackground(let format):
            return "Encoding transparent \(format) data as JPEG requires an explicit background."
        case .nonOpaqueJPEGBackground:
            return "Encoding JPEG with a custom background requires an opaque color."

        case .unsupportedDestinationFormat(let format):
            return "The current environment cannot write the \(format) format."
        case .unsupportedColorSpace:
            return "The requested color space is not available on this platform."
        case .invalidICCProfile:
            return "The supplied ICC profile could not create a color space."

        case .imageDecodeFailed:
            return "Could not decode source pixels."
        case .imageRenderingFailed:
            return "Failed to render image pixels as requested."
        case .imageEncodeFailed(let format):
            return "Failed to encode the image as \(format)."

        case .targetUnsatisfiable(let smallestByteCount):
            if let smallestByteCount {
                return "Could not satisfy the compression target; smallest encoded result was \(smallestByteCount) bytes."
            }

            return "Could not satisfy the compression target."
        case .resourceLimitExceeded(let attemptCount):
            return "Target compression exceeded its resource budget after \(attemptCount) attempts."
        }
    }
}
