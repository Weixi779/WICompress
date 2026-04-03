import Testing
@testable import WICompress

@Suite("Luban Ratio Policy", .tags(.luban))
struct LubanRatioTests {

    // MARK: - calculateLubanRatio

    struct RatioCase: CustomTestStringConvertible {
        let width: Int
        let height: Int
        let expected: Int
        let testDescription: String
    }

    static let ratioCases: [RatioCase] = [
        // Branch 1: aspectRatio ∈ [0.5625, 1], longSide < 1664 → 1
        RatioCase(width: 1200, height: 1000, expected: 1, testDescription: "near-square small image"),
        // 1661 (odd) → ensureEven → 1662, which is < 1664, stays in branch 1
        RatioCase(width: 1661, height: 1661, expected: 1, testDescription: "square just below longSide boundary 1664"),
        // Branch 2: aspectRatio ∈ [0.5625, 1], longSide ∈ [1664, 4990) → 2
        RatioCase(width: 3000, height: 2000, expected: 2, testDescription: "medium landscape image"),
        RatioCase(width: 1664, height: 1664, expected: 2, testDescription: "square at longSide boundary 1664"),
        // Branch 3: aspectRatio ∈ [0.5625, 1], longSide ∈ [4990, 10240) → 4
        RatioCase(width: 8000, height: 6000, expected: 4, testDescription: "large near-square image"),
        RatioCase(width: 4990, height: 4990, expected: 4, testDescription: "square at longSide boundary 4990"),
        // Branch 4: aspectRatio ∈ [0.5625, 1], longSide ≥ 10240 → longSide / 1280
        RatioCase(width: 12800, height: 10000, expected: 10, testDescription: "very large near-square image"),
        // Branch 5: aspectRatio ∈ [0.5, 0.5625), longSide > 1280 → longSide / 1280
        RatioCase(width: 2000, height: 1000, expected: 1, testDescription: "wide image longSide 2000"),
        RatioCase(width: 2560, height: 1280, expected: 2, testDescription: "wide image longSide 2560"),
        // Branch 6: aspectRatio ∈ [0.5, 0.5625), longSide ≤ 1280 → 1
        RatioCase(width: 1200, height: 600, expected: 1, testDescription: "wide small image"),
        RatioCase(width: 1280, height: 640, expected: 1, testDescription: "wide image at longSide boundary 1280"),
        // Branch 7: default (aspectRatio < 0.5) → ceil(longSide / 1280)
        RatioCase(width: 2000, height: 500, expected: 2, testDescription: "very wide image"),
        RatioCase(width: 2560, height: 256, expected: 2, testDescription: "panoramic image"),
    ]

    @Test("Ratio calculation covers all branches", arguments: ratioCases)
    func ratioForBranch(_ ratioCase: RatioCase) {
        let ratio = WIImageUtils.calculateLubanRatio(width: ratioCase.width, height: ratioCase.height)
        #expect(ratio == ratioCase.expected)
    }

    // MARK: - ensureEven

    @Suite("ensureEven", .tags(.luban, .edgeCase))
    struct EnsureEvenTests {

        @Test("Even number is unchanged")
        func evenNumberUnchanged() {
            #expect(WIImageUtils.ensureEven(4) == 4)
            #expect(WIImageUtils.ensureEven(100) == 100)
            #expect(WIImageUtils.ensureEven(1280) == 1280)
        }

        @Test("Odd number is incremented by 1")
        func oddNumberIncremented() {
            #expect(WIImageUtils.ensureEven(1) == 2)
            #expect(WIImageUtils.ensureEven(99) == 100)
            #expect(WIImageUtils.ensureEven(1279) == 1280)
        }

        @Test("Zero remains zero", .tags(.edgeCase))
        func zeroRemainsZero() {
            #expect(WIImageUtils.ensureEven(0) == 0)
        }
    }
}
