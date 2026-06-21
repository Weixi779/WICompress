import Foundation
import ImageIO

final class WIImageSource {
    let data: Data
    let cgImageSource: CGImageSource
    let info: WIImageInfo

    init(data: Data) throws(WICompressError) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw WICompressError.invalidImageData
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw WICompressError.invalidImageData
        }

        guard frameCount == 1 else {
            throw WICompressError.animatedSourceUnsupported(frameCount: frameCount)
        }

        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = properties.intValue(for: kCGImagePropertyPixelWidth),
            let pixelHeight = properties.intValue(for: kCGImagePropertyPixelHeight)
        else {
            throw WICompressError.imageInfoUnavailable
        }

        let typeIdentifier = CGImageSourceGetType(source) as String?
        let format = WIImageFormat(typeIdentifier: typeIdentifier)
        let orientation = properties.intValue(for: kCGImagePropertyOrientation) ?? 1
        let hasGPS = properties.dictionaryExists(for: kCGImagePropertyGPSDictionary)
        let hasMetadata = Self.hasStrippableMetadata(in: properties)
        let hasAlpha = properties.boolValue(for: kCGImagePropertyHasAlpha)
        let isWritable = typeIdentifier.map(Self.canWriteImageTypeIdentifier(_:)) ?? false

        self.data = data
        self.cgImageSource = source
        self.info = WIImageInfo(
            sourceFormat: format,
            typeIdentifier: typeIdentifier,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            orientation: orientation,
            frameCount: frameCount,
            isSourceFormatWritable: isWritable,
            hasMetadata: hasMetadata,
            hasGPS: hasGPS,
            hasGainMap: Self.hasGainMap(in: source),
            hasAlpha: hasAlpha
        )
    }

    private static func canWriteImageTypeIdentifier(_ typeIdentifier: String) -> Bool {
        writableTypeIdentifiers.contains(typeIdentifier)
    }

    private static let writableTypeIdentifiers: Set<String> = {
        guard let writableTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] else {
            return []
        }

        return Set(writableTypes)
    }()

    private static func hasStrippableMetadata(in properties: [CFString: Any]) -> Bool {
        let metadataKeys: [CFString] = [
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyExifDictionary,
            kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyIPTCDictionary,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyMakerAppleDictionary,
            kCGImagePropertyMakerCanonDictionary,
            kCGImagePropertyMakerNikonDictionary,
            kCGImagePropertyMakerMinoltaDictionary,
            kCGImagePropertyMakerFujiDictionary,
            kCGImagePropertyMakerOlympusDictionary,
            kCGImagePropertyMakerPentaxDictionary
        ]

        return metadataKeys.contains { properties.dictionaryExists(for: $0) }
    }

    private static func hasGainMap(in source: CGImageSource) -> Bool {
        if #available(iOS 14.1, macOS 11.0, *) {
            return CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source,
                0,
                kCGImageAuxiliaryDataTypeHDRGainMap
            ) != nil
        }

        return false
    }
}

private extension Dictionary where Key == CFString, Value == Any {
    func intValue(for key: CFString) -> Int? {
        if let value = self[key] as? Int {
            return value
        }

        if let value = self[key] as? NSNumber {
            return value.intValue
        }

        return nil
    }

    func boolValue(for key: CFString) -> Bool? {
        if let value = self[key] as? Bool {
            return value
        }

        if let value = self[key] as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    func dictionaryExists(for key: CFString) -> Bool {
        guard let dictionary = self[key] as? [AnyHashable: Any] else {
            return false
        }

        return !dictionary.isEmpty
    }
}
