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
