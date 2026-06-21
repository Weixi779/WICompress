import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum WIImageFormat: Sendable, Equatable {
    case jpeg
    case png
    case heif
    case unknown
    
    public var isHEIF: Bool {
        return self == .heif
    }

    init(typeIdentifier: String?) {
        guard
            let typeIdentifier,
            let type = UTType(typeIdentifier)
        else {
            self = .unknown
            return
        }

        if type.conforms(to: .jpeg) {
            self = .jpeg
        } else if type.conforms(to: .png) {
            self = .png
        } else if type.conforms(to: .heic) || type.conforms(to: .heif) {
            self = .heif
        } else {
            self = .unknown
        }
    }

    var supportsLossyQuality: Bool {
        switch self {
        case .jpeg, .heif:
            return true
        case .png, .unknown:
            return false
        }
    }

    public init(data: Data) {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let uti = CGImageSourceGetType(imageSource)
        else {
            self = .unknown
            return
        }

        self.init(typeIdentifier: uti as String)
    }
}
