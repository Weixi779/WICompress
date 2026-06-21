import Foundation

struct WIWritePlan: Sendable, Equatable {
    var path: WIWritePath
    var destinationFormat: WIImageFormat
    var destinationTypeIdentifier: String
    var maxPixelSize: Int?
    var metadataPolicy: WIMetadataPolicy
    var quality: Double?
}

enum WIWritePath: Sendable, Equatable {
    case returnOriginal
    case copyFromSource
    case redrawBitmap
}
