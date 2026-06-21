import Foundation

public struct WICompressOptions: Sendable, Equatable {
    public var resize: WIResizePolicy
    public var format: WIFormatPolicy
    public var metadata: WIMetadataPolicy
    public var quality: WIQualityPolicy

    public init(
        resize: WIResizePolicy = .luban,
        format: WIFormatPolicy = .preserve,
        metadata: WIMetadataPolicy = .strip,
        quality: WIQualityPolicy = .compression(0.6)
    ) {
        self.resize = resize
        self.format = format
        self.metadata = metadata
        self.quality = quality
    }

    public static let `default` = WICompressOptions()
}
