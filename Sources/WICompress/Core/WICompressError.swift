import Foundation

public enum WICompressError: Error, Sendable, Equatable {
    case fileReadFailed(URL)
    case invalidImageData
    case imageInfoUnavailable
    case unsupportedSourceFormat(String?)
    case unsupportedDestinationFormat(WIImageFormat)
    case animatedSourceUnsupported(frameCount: Int)
    case writePlanUnavailable
    case thumbnailCreationFailed
    case destinationCreationFailed(WIImageFormat)
    case encodeFailed(WIImageFormat)
}
