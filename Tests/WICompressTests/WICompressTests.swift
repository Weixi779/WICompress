import Foundation
import Testing
@testable import WICompress

@Test func lubanRatioForSmallImageShouldBeOne() {
    let ratio = WIImageUtils.calculateLubanRatio(width: 1200, height: 1000)
    #expect(ratio == 1)
}

@Test func lubanRatioForMediumImageShouldBeTwo() {
    let ratio = WIImageUtils.calculateLubanRatio(width: 3000, height: 2000)
    #expect(ratio == 2)
}

@Test func imageFormatShouldBeUnknownForEmptyData() {
    let format = WIImageFormat(data: Data())
    if case .unknown = format {
        #expect(Bool(true))
    } else {
        #expect(Bool(false))
    }
}
