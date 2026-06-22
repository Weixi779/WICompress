//
//  WIWritePlanResolverTests.swift
//  WICompressTests
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import Testing
@testable import WICompress

@Suite("WIWritePlanResolver", .tags(.imageIOCore, .compression))
struct WIWritePlanResolverTests {

    struct QualityCase: CustomTestStringConvertible, Sendable {
        let resourceName: String
        let resourceExtension: String
        let expectedFormat: WIImageFormat
        let expectedCompressionQuality: Double?
        let testDescription: String
    }

    static let qualityCases: [QualityCase] = [
        QualityCase(
            resourceName: "real_jpeg_2098x1350_landscape",
            resourceExtension: "jpg",
            expectedFormat: .jpeg,
            expectedCompressionQuality: 0.25,
            testDescription: "JPEG receives lossy quality"
        ),
        QualityCase(
            resourceName: "real_heic_4032x3024_o1_gps_hdr",
            resourceExtension: "heic",
            expectedFormat: .heif,
            expectedCompressionQuality: 0.25,
            testDescription: "HEIC receives lossy quality"
        ),
        QualityCase(
            resourceName: "real_png_814x386_wide",
            resourceExtension: "png",
            expectedFormat: .png,
            expectedCompressionQuality: nil,
            testDescription: "PNG ignores lossy quality"
        ),
    ]

    @Test(".quality(.none) never resolves lossy quality", arguments: qualityCases)
    func qualityNoneDoesNotSetLossyQuality(_ qualityCase: QualityCase) throws {
        let info = try Self.imageInfo(for: qualityCase)

        let plan = try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .none,
                format: .preserve,
                metadata: .preserve,
                quality: .none
            ),
            info: info
        )

        #expect(info.sourceFormat == qualityCase.expectedFormat)
        #expect(plan.quality == nil)
    }

    @Test(".quality(.compression) resolves only for lossy destination formats", arguments: qualityCases)
    func compressionQualityMatchesDestinationFormat(_ qualityCase: QualityCase) throws {
        let info = try Self.imageInfo(for: qualityCase)

        let plan = try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .none,
                format: .preserve,
                metadata: .preserve,
                quality: .compression(0.25)
            ),
            info: info
        )

        #expect(info.sourceFormat == qualityCase.expectedFormat)
        #expect(plan.quality == qualityCase.expectedCompressionQuality)
    }

    @Test("Non-writable preserve source can return original when policies are already satisfied")
    func nonWritableSourceReturnsOriginalWhenPoliciesAllowIt() throws {
        let info = WIImageInfo(
            sourceFormat: .jpeg,
            typeIdentifier: "public.jpeg",
            pixelWidth: 100,
            pixelHeight: 100,
            orientation: 1,
            frameCount: 1,
            isSourceFormatWritable: false,
            hasMetadata: false,
            hasGPS: false,
            hasGainMap: false,
            hasAlpha: false
        )

        let plan = try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .none,
                format: .preserve,
                metadata: .preserve,
                quality: .compression(0.6)
            ),
            info: info
        )

        #expect(plan.path == .returnOriginal)
        #expect(plan.destinationFormat == .jpeg)
    }

    @Test("Non-writable source throws when strip policy requires rewriting")
    func nonWritableSourceThrowsWhenPolicyRequiresRewrite() {
        let info = WIImageInfo(
            sourceFormat: .jpeg,
            typeIdentifier: "public.jpeg",
            pixelWidth: 100,
            pixelHeight: 100,
            orientation: 1,
            frameCount: 1,
            isSourceFormatWritable: false,
            hasMetadata: true,
            hasGPS: true,
            hasGainMap: false,
            hasAlpha: false
        )

        #expect(throws: WICompressError.unsupportedDestinationFormat(.jpeg)) {
            _ = try WIWritePlanResolver.resolve(
                options: WICompressOptions(
                    resize: .none,
                    format: .preserve,
                    metadata: .strip,
                    quality: .compression(0.6)
                ),
                info: info
            )
        }
    }

    private static func imageInfo(for qualityCase: QualityCase) throws -> WIImageInfo {
        let url = try #require(
            Bundle.module.url(
                forResource: qualityCase.resourceName,
                withExtension: qualityCase.resourceExtension,
                subdirectory: "Resources"
            ),
            "Missing fixture: \(qualityCase.resourceName).\(qualityCase.resourceExtension)"
        )
        let data = try Data(contentsOf: url)
        return try WIImageSource(data: data).info
    }
}
