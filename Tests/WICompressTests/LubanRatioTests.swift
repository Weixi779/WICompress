import Testing
@testable import WICompress

@Suite("Luban Ratio Policy", .tags(.luban))
struct LubanRatioTests {

    // MARK: - calculateLubanRatio

    struct RatioCase: CustomTestStringConvertible, Sendable {
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
        // Branch 7: default (aspectRatio < 0.5) → ceil(shortSide / 1280)
        // (original Luban constrains the SHORT side here; dividing the long side
        // over-shrinks long images. See WIImageUtils default branch.)
        RatioCase(width: 2000, height: 500, expected: 1, testDescription: "very wide image, short side 500"),
        RatioCase(width: 2560, height: 256, expected: 1, testDescription: "panoramic image, short side 256"),
        RatioCase(width: 1440, height: 3200, expected: 2, testDescription: "long screenshot, short side 1440"),
        RatioCase(width: 3000, height: 8000, expected: 3, testDescription: "tall image, short side 3000"),
        RatioCase(width: 12000, height: 5000, expected: 4, testDescription: "panorama, short side 5000"),
        RatioCase(width: 1242, height: 22080, expected: 1, testDescription: "extreme long image stays unscaled"),
    ]

    @Test("Ratio calculation covers all branches", arguments: ratioCases)
    func ratioForBranch(_ ratioCase: RatioCase) {
        let ratio = WIImageUtils.calculateLubanRatio(width: ratioCase.width, height: ratioCase.height)
        #expect(ratio == ratioCase.expected)
    }

    // MARK: - ensureEven

    @Suite("ensureEven", .tags(.luban))
    struct EnsureEvenTests {

        struct EnsureEvenCase: CustomTestStringConvertible, Sendable {
            let value: Int
            let expected: Int
            let testDescription: String
        }

        static let ensureEvenCases: [EnsureEvenCase] = [
            EnsureEvenCase(value: 4, expected: 4, testDescription: "even number 4 is unchanged"),
            EnsureEvenCase(value: 100, expected: 100, testDescription: "even number 100 is unchanged"),
            EnsureEvenCase(value: 1280, expected: 1280, testDescription: "even boundary 1280 is unchanged"),
            EnsureEvenCase(value: 1, expected: 2, testDescription: "odd number 1 increments to 2"),
            EnsureEvenCase(value: 99, expected: 100, testDescription: "odd number 99 increments to 100"),
            EnsureEvenCase(value: 1279, expected: 1280, testDescription: "odd boundary 1279 increments to 1280"),
            EnsureEvenCase(value: 0, expected: 0, testDescription: "zero remains zero"),
            EnsureEvenCase(value: -3, expected: -2, testDescription: "negative odd increments toward even"),
        ]

        @Test("ensureEven returns the documented even value", arguments: ensureEvenCases)
        func ensureEven(_ ensureEvenCase: EnsureEvenCase) {
            #expect(WIImageUtils.ensureEven(ensureEvenCase.value) == ensureEvenCase.expected)
        }
    }
}
