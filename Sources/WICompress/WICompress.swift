import Foundation

public struct WICompress: Sendable {

    public static func compress(
        _ data: Data,
        options: WICompressOptions = .default
    ) throws -> Data {
        let imageSource = try WIImageSource(data: data)
        let writePlan = try WIWritePlanResolver.resolve(options: options, info: imageSource.info)
        let encodedData = try WIImageEncoder.encode(imageSource, plan: writePlan)

        if writePlan.path != .returnOriginal,
           encodedData.count >= data.count,
           WIWritePlanResolver.canReturnOriginalForSizeGuard(options: options, info: imageSource.info) {
            return data
        }

        return encodedData
    }

    public static func compress(
        contentsOf url: URL,
        options: WICompressOptions = .default
    ) throws -> Data {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw WICompressError.fileReadFailed(url)
        }

        return try compress(data, options: options)
    }
}

#if os(iOS)
import UIKit

extension WICompress {

    /// Resize Image By luban Algorithm
    /// - Parameter image: The image to be compressed
    /// - Returns: The resized `UIImage` if the operation succeeds, or the original image if resizing fails.
    public static func resizeImage(_ image: UIImage) -> UIImage {
        let width = Int(image.size.width)
        let height = Int(image.size.height)

        let resizeRatio = WIImageUtils.calculateLubanRatio(width: width, height: height)
        let compressor = WIImageCompressor(image: image)

        return compressor.resize(by: resizeRatio) ?? image
    }
    
    /// Compress the image to the specified format data
    /// It is strongly recommended to provide the data when the image source is HEIC; otherwise, the compression results will be poor.
    /// - Parameters:
    ///   - image: The image to be compressed
    ///   - quality: Compression quality (0.0 - 1.0), default is 0.6
    ///   - formatData: Data used to determine the image format, defaults to .jpeg if nil
    /// - Returns: Compressed image data, or nil if conversion fails
    public static func compressImage(
        _ image: UIImage,
        quality: CGFloat = 0.6,
        formatData: Data? = nil
    ) -> Data? {
        let format = WIImageFormat(data: formatData ?? Data())
        
        let resizedImage = resizeImage(image)
        
        let compressor = WIImageCompressor(image: resizedImage)
        return compressor.compress(format: format, quality: quality)
    }
}
#endif
