import Foundation

public struct WICompress: Sendable {

    public static func compress(
        _ data: Data,
        options: WICompressOptions = .default
    ) throws(WICompressError) -> Data {
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
    ) throws(WICompressError) -> Data {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw WICompressError.fileReadFailed(url)
        }

        return try compress(data, options: options)
    }
}
