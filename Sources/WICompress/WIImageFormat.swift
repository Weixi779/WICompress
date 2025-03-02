import Foundation
import CoreImage
import UniformTypeIdentifiers

enum WIImageFormat {
    case jpeg
    case png
    case heif
    case unknown
    
    init(data: Data) {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let uti = CGImageSourceGetType(imageSource),
            let type = UTType(uti as String)
        else {
            self = .unknown
            return
        }
        
        if type.conforms(to: .jpeg) {
            self = .jpeg
        } else if type.conforms(to: .png) {
            self = .png
        } else if type.conforms(to: .heif) || type.conforms(to: .heic) {
            self = .heif
        } else {
            self = .unknown
        }
    }
}
