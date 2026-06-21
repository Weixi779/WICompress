import Foundation
import ImageIO

public enum WIImageFormat: Sendable, Equatable {
    case jpeg
    case png
    case heif
    case unknown
    
    public var isHEIF: Bool {
        return self == .heif
    }
    
    public init(data: Data) {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let uti = CGImageSourceGetType(imageSource)
        else {
            self = .unknown
            return
        }

        let utiString = (uti as String).lowercased()
        if utiString.contains("jpeg") || utiString.contains("jpg") {
            self = .jpeg
        } else if utiString.contains("png") {
            self = .png
        } else if utiString.contains("heif") || utiString.contains("heic") {
            self = .heif
        } else {
            self = .unknown
        }
    }
}
