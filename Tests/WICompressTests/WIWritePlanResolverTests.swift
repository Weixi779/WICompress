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

    struct ExplicitFormatCase: CustomTestStringConvertible, Sendable {
        let format: WIFormatPolicy
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

    static let explicitFormatCases: [ExplicitFormatCase] = [
        ExplicitFormatCase(
            format: .jpeg(background: .disallow),
            expectedFormat: .jpeg,
            expectedCompressionQuality: 0.4,
            testDescription: "explicit JPEG uses lossy quality"
        ),
        ExplicitFormatCase(
            format: .pngIfAlphaOtherwiseJPEG,
            expectedFormat: .jpeg,
            expectedCompressionQuality: 0.4,
            testDescription: "alpha-aware format uses JPEG for opaque sources"
        ),
        ExplicitFormatCase(
            format: .png,
            expectedFormat: .png,
            expectedCompressionQuality: nil,
            testDescription: "explicit PNG ignores lossy quality"
        ),
        ExplicitFormatCase(
            format: .heic,
            expectedFormat: .heif,
            expectedCompressionQuality: 0.4,
            testDescription: "explicit HEIC uses lossy quality"
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

    @Test("Explicit destination formats force redraw and resolve quality by target format", arguments: explicitFormatCases)
    func explicitDestinationFormatResolvesWritePlan(_ explicitFormatCase: ExplicitFormatCase) throws {
        let info = try Self.imageInfo(
            resourceName: "real_jpeg_2098x1350_landscape",
            resourceExtension: "jpg"
        )

        let plan = try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .none,
                format: explicitFormatCase.format,
                metadata: .preserve,
                quality: .compression(0.4)
            ),
            info: info
        )

        #expect(plan.path == .redrawBitmap)
        #expect(plan.destinationFormat == explicitFormatCase.expectedFormat)
        #expect(plan.quality == explicitFormatCase.expectedCompressionQuality)
    }

    @Test("Transparent source requires an explicit JPEG background")
    func transparentSourceRequiresJPEGBackground() throws {
        let info = try Self.imageInfo(
            resourceName: "real_png_1086x1630_alpha",
            resourceExtension: "png"
        )

        #expect(throws: WICompressError.transparentSourceRequiresBackground(.png)) {
            _ = try WIWritePlanResolver.resolve(
                options: WICompressOptions(
                    resize: .none,
                    format: .jpeg(background: .disallow),
                    metadata: .strip,
                    quality: .compression(0.6)
                ),
                info: info
            )
        }
    }

    @Test(".maxPixel caps the longest side without upscaling")
    func maxPixelResolvesCapWithoutUpscaling() throws {
        let info = try Self.imageInfo(
            resourceName: "real_jpeg_2098x1350_landscape",
            resourceExtension: "jpg"
        )

        let cappedPlan = try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .maxPixel(600),
                format: .preserve,
                metadata: .preserve,
                quality: .none
            ),
            info: info
        )
        let noUpscalePlan = try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .maxPixel(5000),
                format: .preserve,
                metadata: .preserve,
                quality: .none
            ),
            info: info
        )

        #expect(cappedPlan.maxPixelSize == 600)
        #expect(cappedPlan.path == .copyFromSource)
        #expect(noUpscalePlan.maxPixelSize == nil)
        #expect(noUpscalePlan.path == .returnOriginal)
    }

    @Test(".fit upscales only when both sides are below the minimum size")
    func fitUpscalesSmallImages() throws {
        let info = Self.syntheticInfo(width: 20, height: 20)
        let options = WICompressOptions(
            resize: .fit(
                minSize: WISize(width: 40, height: 50),
                maxSize: WISize(width: 400, height: 467)
            ),
            format: .preserve,
            metadata: .preserve,
            quality: .none
        )

        let plan = try WIWritePlanResolver.resolve(options: options, info: info)

        #expect(plan.path == .redrawBitmap)
        #expect(plan.maxPixelSize == nil)
        #expect(plan.targetPixelSize == WIPixelSize(width: 40, height: 40))
        #expect(WIWritePlanResolver.canReturnOriginalForSizeGuard(options: options, info: info) == false)
    }

    @Test(".fit downscales only when both sides are above the maximum size")
    func fitDownscalesLargeImages() throws {
        let info = Self.syntheticInfo(width: 720, height: 1080)
        let options = WICompressOptions(
            resize: .fit(
                minSize: WISize(width: 40, height: 50),
                maxSize: WISize(width: 400, height: 467)
            ),
            format: .preserve,
            metadata: .preserve,
            quality: .none
        )

        let plan = try WIWritePlanResolver.resolve(options: options, info: info)

        #expect(plan.path == .copyFromSource)
        #expect(plan.maxPixelSize == 600)
        #expect(plan.targetPixelSize == WIPixelSize(width: 400, height: 600))
        #expect(WIWritePlanResolver.canReturnOriginalForSizeGuard(options: options, info: info) == false)
    }

    @Test(".fit leaves the asset unchanged when either side is already in range")
    func fitLeavesImagesWithOneSideInRangeUnchanged() throws {
        let info = Self.syntheticInfo(width: 120, height: 20)
        let options = WICompressOptions(
            resize: .fit(
                minSize: WISize(width: 40, height: 50),
                maxSize: WISize(width: 400, height: 467)
            ),
            format: .preserve,
            metadata: .preserve,
            quality: .none
        )

        let plan = try WIWritePlanResolver.resolve(options: options, info: info)

        #expect(plan.path == .returnOriginal)
        #expect(plan.maxPixelSize == nil)
        #expect(plan.targetPixelSize == nil)
        #expect(WIWritePlanResolver.canReturnOriginalForSizeGuard(options: options, info: info) == true)
    }

    @Test(".fit uses EXIF-oriented display dimensions")
    func fitUsesOrientedDisplayDimensions() throws {
        let info = Self.syntheticInfo(width: 20, height: 30, orientation: 6)
        let plan = try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .fit(
                    minSize: WISize(width: 40, height: 50),
                    maxSize: WISize(width: 400, height: 467)
                ),
                format: .preserve,
                metadata: .preserve,
                quality: .none
            ),
            info: info
        )

        #expect(plan.path == .redrawBitmap)
        #expect(plan.targetPixelSize == WIPixelSize(width: 40, height: 27))
    }

    @Test("Explicit format is never return-original eligible")
    func explicitFormatIsNeverReturnOriginalEligible() throws {
        let info = try Self.imageInfo(
            resourceName: "real_png_814x386_wide",
            resourceExtension: "png"
        )

        let plan = try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .none,
                format: .png,
                metadata: .preserve,
                quality: .none
            ),
            info: info
        )

        #expect(plan.path == .redrawBitmap)
        #expect(WIWritePlanResolver.canReturnOriginalForSizeGuard(
            options: WICompressOptions(
                resize: .none,
                format: .png,
                metadata: .preserve,
                quality: .none
            ),
            info: info
        ) == false)
        #expect(WIWritePlanResolver.canReturnOriginalForSizeGuard(
            options: WICompressOptions(
                resize: .none,
                format: .pngIfAlphaOtherwiseJPEG,
                metadata: .preserve,
                quality: .none
            ),
            info: info
        ) == false)
    }

    @Test("Alpha-aware format uses PNG for transparent sources")
    func alphaAwareFormatUsesPNGForTransparentSource() throws {
        let info = try Self.imageInfo(
            resourceName: "real_png_1086x1630_alpha",
            resourceExtension: "png"
        )
        try #require(info.hasAlpha == true, "Fixture should contain alpha")

        let plan = try WIWritePlanResolver.resolve(
            options: WICompressOptions(
                resize: .none,
                format: .pngIfAlphaOtherwiseJPEG,
                metadata: .preserve,
                quality: .compression(0.4)
            ),
            info: info
        )

        #expect(plan.path == .redrawBitmap)
        #expect(plan.destinationFormat == .png)
        #expect(plan.quality == nil)
        #expect(plan.jpegBackground == nil)
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
        try imageInfo(
            resourceName: qualityCase.resourceName,
            resourceExtension: qualityCase.resourceExtension
        )
    }

    private static func imageInfo(resourceName: String, resourceExtension: String) throws -> WIImageInfo {
        let url = try #require(
            Bundle.module.url(
                forResource: resourceName,
                withExtension: resourceExtension,
                subdirectory: "Resources"
            ),
            "Missing fixture: \(resourceName).\(resourceExtension)"
        )
        let data = try Data(contentsOf: url)
        return try WIImageSource(data: data).info
    }

    private static func syntheticInfo(
        width: Int,
        height: Int,
        orientation: Int = 1
    ) -> WIImageInfo {
        WIImageInfo(
            sourceFormat: .png,
            typeIdentifier: "public.png",
            pixelWidth: width,
            pixelHeight: height,
            orientation: orientation,
            frameCount: 1,
            isSourceFormatWritable: true,
            hasMetadata: false,
            hasGPS: false,
            hasGainMap: false,
            hasAlpha: true
        )
    }
}
