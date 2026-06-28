//
//  WICompressError.swift
//  WICompress
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

/// Errors thrown while inspecting, planning, or encoding an image.
public enum WICompressError: Error, Sendable, Equatable {
    /// The file URL could not be read.
    case fileReadFailed(URL)
    /// The input data is not a decodable image.
    case invalidImageData
    /// ImageIO could not provide required image facts.
    case imageInfoUnavailable
    /// The source container is not supported.
    case unsupportedSourceFormat(String?)
    /// The current platform cannot write the requested destination format.
    case unsupportedDestinationFormat(WIImageFormat)
    /// Transparent source data needs an explicit background before JPEG encoding.
    case transparentSourceRequiresBackground(WIImageFormat)
    /// The requested color space is not available on the current platform.
    case unsupportedColorSpace
    /// The supplied ICC profile could not create a color space.
    case invalidICCProfile
    /// Image rendering into the requested color space failed.
    case colorConversionFailed
    /// JPEG background colors must be fully opaque.
    case nonOpaqueJPEGBackground
    /// Multi-frame image data is not supported.
    case animatedSourceUnsupported(frameCount: Int)
    /// The options and image facts could not produce a valid write plan.
    case writePlanUnavailable
    /// ImageIO could not create the downsampled bitmap.
    case thumbnailCreationFailed
    /// ImageIO could not create an output destination.
    case destinationCreationFailed(WIImageFormat)
    /// ImageIO failed to finalize the encoded image.
    case encodeFailed(WIImageFormat)
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
        case .unsupportedDestinationFormat(let format):
            return "The current environment cannot write the \(format) format."
        case .transparentSourceRequiresBackground(let format):
            return "Encoding transparent \(format) data as JPEG requires an explicit background."
        case .unsupportedColorSpace:
            return "The requested color space is not available on this platform."
        case .invalidICCProfile:
            return "The supplied ICC profile could not create a color space."
        case .colorConversionFailed:
            return "Failed to render the image into the requested color space."
        case .nonOpaqueJPEGBackground:
            return "Encoding JPEG with a custom background requires an opaque color."
        case .animatedSourceUnsupported(let frameCount):
            return "Animated images are not supported (\(frameCount) frames)."
        case .writePlanUnavailable:
            return "Could not resolve a valid write plan for the given options."
        case .thumbnailCreationFailed:
            return "Failed to create a downsampled image during compression."
        case .destinationCreationFailed(let format):
            return "Failed to create an image destination for the \(format) format."
        case .encodeFailed(let format):
            return "Failed to encode the image as \(format)."
        }
    }
}
