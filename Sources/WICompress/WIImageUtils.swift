import Foundation

public struct WIImageUtils {
    
    /// Ensures a given size is even by adding 1 if it's odd
    /// - Parameter size: The size to ensure is even
    /// - Returns: An even integer
    static func ensureEven(_ size: Int) -> Int {
        return size % 2 == 1 ? size + 1 : size
    }
    
    /// Calculates the compression ratio using the Luban algorithm.
    /// - Parameters:
    ///   - width: The width of the image.
    ///   - height: The height of the image.
    /// - Returns: The computed compression ratio.
    public static func calculateLubanRatio(width: Int, height: Int) -> Int {
        let longSide = max(ensureEven(width), ensureEven(height))
        let shortSide = min(ensureEven(width), ensureEven(height))
        let aspectRatio = Double(shortSide) / Double(longSide)

        switch aspectRatio {
        case 0.5625...1 where longSide < 1664:
            return 1
        case 0.5625...1 where longSide < 4990:
            return 2
        case 0.5625...1 where longSide < 10240:
            return 4
        case 0.5625...1:
            return max(longSide / 1280, 1)
        case 0.5..<0.5625:
            return longSide > 1280 ? max(longSide / 1280, 1) : 1
        default:
            return Int(ceil(Double(longSide) / 1280.0))
        }
    }
}