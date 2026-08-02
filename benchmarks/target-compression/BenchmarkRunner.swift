//
//  BenchmarkRunner.swift
//  TargetCompressionBenchmark
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import CoreGraphics
import Foundation
import WICompress
import WIImageIO

struct BenchmarkRunner {
    let configuration: BenchmarkConfiguration

    func run() throws -> BenchmarkReport {
        let corpus = try BenchmarkCorpus.load(inputURL: configuration.inputURL)
        try prepareArtifactDirectory()

        print("fixtures: \(corpus.urls.count)")
        print("runs: \(configuration.runs), warmup: \(configuration.warmupRuns)")

        var reports: [BenchmarkCaseReport] = []
        reports.reserveCapacity(corpus.urls.count * configuration.budgets.count)

        for url in corpus.urls {
            let fixture = try corpus.loadFixture(url)
            for budget in configuration.budgets {
                let targetByteCount = budget.byteCount(
                    for: fixture.descriptor.byteCount
                )
                print(
                    "running: \(fixture.name), \(fixture.outputFamily.rawValue), "
                        + "\(budget.label) -> \(targetByteCount) bytes"
                )
                reports.append(
                    try run(
                        fixture: fixture,
                        budget: budget,
                        targetByteCount: targetByteCount
                    )
                )
            }
        }

        return BenchmarkReport(
            schemaVersion: 1,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            strategyID: "current",
            environment: .current,
            runs: configuration.runs,
            warmupRuns: configuration.warmupRuns,
            cases: reports
        )
    }

    private func run(
        fixture: BenchmarkFixture,
        budget: BenchmarkBudget,
        targetByteCount: Int
    ) throws -> BenchmarkCaseReport {
        let target = try WICompressionTarget(
            maxBytes: targetByteCount,
            sizing: .original,
            output: WIImageOutput(
                representation: fixture.outputFamily.representation,
                metadata: .strip,
                colorSpace: .convert(to: .sRGB)
            )
        )

        if let warmupFailure = warmUp(
            fixture: fixture,
            target: target
        ) {
            return BenchmarkCaseReport(
                fixture: fixture,
                budget: budget,
                targetByteCount: targetByteCount,
                status: .warmupFailed,
                warmupFailure: warmupFailure,
                artifactFileName: nil,
                runs: []
            )
        }

        var runs: [BenchmarkRunReport] = []
        var representativeData: Data?
        runs.reserveCapacity(configuration.runs)

        for runIndex in 0..<configuration.runs {
            let start = DispatchTime.now().uptimeNanoseconds
            do {
                let result = try autoreleasepool {
                    try WICompressor.compress(fixture.data, to: target)
                }
                let duration = DispatchTime.now().uptimeNanoseconds - start

                do {
                    let output = try validate(
                        result,
                        fixture: fixture,
                        targetByteCount: targetByteCount
                    )
                    runs.append(
                        BenchmarkRunReport(
                            index: runIndex,
                            durationNanoseconds: duration,
                            outcome: .success,
                            output: output,
                            errorCode: nil,
                            errorDescription: nil
                        )
                    )
                    if representativeData == nil {
                        representativeData = result.data
                    }
                } catch let error as BenchmarkValidationError {
                    runs.append(
                        BenchmarkRunReport(
                            index: runIndex,
                            durationNanoseconds: duration,
                            outcome: .validationFailure,
                            output: nil,
                            errorCode: error.benchmarkCode,
                            errorDescription: error.localizedDescription
                        )
                    )
                } catch {
                    runs.append(
                        BenchmarkRunReport(
                            index: runIndex,
                            durationNanoseconds: duration,
                            outcome: .validationFailure,
                            output: nil,
                            errorCode: "outputInspectionFailed",
                            errorDescription: error.localizedDescription
                        )
                    )
                }
            } catch let error as WICompressError {
                let duration = DispatchTime.now().uptimeNanoseconds - start
                runs.append(
                    BenchmarkRunReport(
                        index: runIndex,
                        durationNanoseconds: duration,
                        outcome: .failure,
                        output: nil,
                        errorCode: error.benchmarkCode,
                        errorDescription: error.localizedDescription
                    )
                )
            } catch {
                let duration = DispatchTime.now().uptimeNanoseconds - start
                runs.append(
                    BenchmarkRunReport(
                        index: runIndex,
                        durationNanoseconds: duration,
                        outcome: .failure,
                        output: nil,
                        errorCode: "unexpectedError",
                        errorDescription: error.localizedDescription
                    )
                )
            }
        }

        let status = BenchmarkCaseStatus.resolve(
            runs: runs,
            targetByteCount: targetByteCount
        )
        let artifactFileName: String?
        if status == .passed, let representativeData {
            artifactFileName = try writeArtifact(
                representativeData,
                fixture: fixture,
                budget: budget,
                targetByteCount: targetByteCount
            )
        } else {
            artifactFileName = nil
        }

        return BenchmarkCaseReport(
            fixture: fixture,
            budget: budget,
            targetByteCount: targetByteCount,
            status: status,
            warmupFailure: nil,
            artifactFileName: artifactFileName,
            runs: runs
        )
    }

    private func warmUp(
        fixture: BenchmarkFixture,
        target: WICompressionTarget
    ) -> BenchmarkWarmupFailure? {
        for runIndex in 0..<configuration.warmupRuns {
            do {
                _ = try autoreleasepool {
                    try WICompressor.compress(fixture.data, to: target)
                }
            } catch let error as WICompressError {
                return BenchmarkWarmupFailure(
                    index: runIndex,
                    errorCode: error.benchmarkCode,
                    errorDescription: error.localizedDescription
                )
            } catch {
                return BenchmarkWarmupFailure(
                    index: runIndex,
                    errorCode: "unexpectedError",
                    errorDescription: error.localizedDescription
                )
            }
        }
        return nil
    }

    private func validate(
        _ result: WIResult,
        fixture: BenchmarkFixture,
        targetByteCount: Int
    ) throws -> BenchmarkOutputReport {
        let reader = try ImageReader(result.data)
        let descriptor = reader.descriptor
        let frame = try reader.image()

        guard result.data.count == result.byteCount else {
            throw BenchmarkValidationError.inconsistentByteCount
        }
        guard descriptor.format == result.format else {
            throw BenchmarkValidationError.inconsistentFormat
        }
        guard descriptor.orientation == .up else {
            throw BenchmarkValidationError.orientationWasNotNormalized
        }
        guard
            descriptor.pixelSize == result.pixelSize,
            descriptor.orientedPixelSize == result.pixelSize,
            frame.image.width == result.pixelSize.width,
            frame.image.height == result.pixelSize.height
        else {
            throw BenchmarkValidationError.inconsistentPixelSize
        }
        guard descriptor.frameCount == 1 else {
            throw BenchmarkValidationError.animatedOutput(descriptor.frameCount)
        }
        // ImageIO may synthesize TIFF/Exif destination facts. Strip validation
        // targets source-carried privacy metadata instead.
        let forbiddenMetadata: ImageMetadataOptions = [
            .gps,
            .iptc,
            .makerNotes
        ]
        guard descriptor.metadata.intersection(forbiddenMetadata).isEmpty else {
            throw BenchmarkValidationError.sourceMetadataWasRetained
        }
        guard frame.image.colorSpace?.name == CGColorSpace.sRGB else {
            throw BenchmarkValidationError.outputIsNotSRGB
        }
        guard result.data.count <= targetByteCount else {
            throw BenchmarkValidationError.hardLimitViolation(
                actual: result.data.count,
                target: targetByteCount
            )
        }
        guard descriptor.format == fixture.outputFamily.imageFormat else {
            throw BenchmarkValidationError.unexpectedOutputFamily
        }

        return BenchmarkOutputReport(
            result,
            sha256: result.data.sha256
        )
    }

    private func prepareArtifactDirectory() throws {
        guard let directory = configuration.artifactDirectoryURL else {
            return
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func writeArtifact(
        _ data: Data,
        fixture: BenchmarkFixture,
        budget: BenchmarkBudget,
        targetByteCount: Int
    ) throws -> String? {
        guard let directory = configuration.artifactDirectoryURL else {
            return nil
        }

        let sourceName = fixture.url.deletingPathExtension().lastPathComponent
        let sourceID = fixture.sha256.prefix(12)
        let budgetName = budget.label.replacingOccurrences(of: ".", with: "_")
        let fileName = "\(sourceName)--\(sourceID)--\(budgetName)--\(targetByteCount)"
            + ".\(fixture.outputFamily.fileExtension)"
        try data.write(
            to: directory.appendingPathComponent(fileName),
            options: .atomic
        )
        return fileName
    }
}

enum BenchmarkValidationError: Error, LocalizedError {
    case animatedOutput(Int)
    case hardLimitViolation(actual: Int, target: Int)
    case inconsistentByteCount
    case inconsistentFormat
    case inconsistentPixelSize
    case orientationWasNotNormalized
    case outputIsNotSRGB
    case sourceMetadataWasRetained
    case unexpectedOutputFamily

    var benchmarkCode: String {
        switch self {
        case .hardLimitViolation:
            return "hardLimitViolation"
        default:
            return "benchmarkValidationFailed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .animatedOutput(let frameCount):
            return "Benchmark output unexpectedly contains \(frameCount) frames."
        case .hardLimitViolation(let actual, let target):
            return "Benchmark output contains \(actual) bytes, exceeding target \(target)."
        case .inconsistentByteCount:
            return "Independent output inspection found an inconsistent byte count."
        case .inconsistentFormat:
            return "Independent output inspection found an inconsistent format."
        case .inconsistentPixelSize:
            return "Independent output inspection found an inconsistent pixel size."
        case .orientationWasNotNormalized:
            return "Benchmark output orientation was not normalized to up."
        case .outputIsNotSRGB:
            return "Benchmark output is not sRGB."
        case .sourceMetadataWasRetained:
            return "Benchmark output retained GPS, IPTC, or maker-note metadata."
        case .unexpectedOutputFamily:
            return "Benchmark output does not match the requested container family."
        }
    }
}

private extension BenchmarkOutputFamily {
    var imageFormat: ImageFormat {
        switch self {
        case .jpeg:
            return .jpeg
        case .heif:
            return .heif
        case .png:
            return .png
        }
    }
}

private extension WICompressError {
    var benchmarkCode: String {
        switch self {
        case .fileReadFailed:
            return "fileReadFailed"
        case .invalidImageData:
            return "invalidImageData"
        case .imageInfoUnavailable:
            return "imageInfoUnavailable"
        case .unsupportedSourceFormat:
            return "unsupportedSourceFormat"
        case .animatedSourceUnsupported:
            return "animatedSourceUnsupported"
        case .invalidCrop:
            return "invalidCrop"
        case .invalidResizing:
            return "invalidResizing"
        case .invalidTarget:
            return "invalidTarget"
        case .transparentSourceRequiresBackground:
            return "transparentSourceRequiresBackground"
        case .nonOpaqueJPEGBackground:
            return "nonOpaqueJPEGBackground"
        case .unsupportedDestinationFormat:
            return "unsupportedDestinationFormat"
        case .unsupportedColorSpace:
            return "unsupportedColorSpace"
        case .invalidICCProfile:
            return "invalidICCProfile"
        case .imageDecodeFailed:
            return "imageDecodeFailed"
        case .imageRenderingFailed:
            return "imageRenderingFailed"
        case .imageEncodeFailed:
            return "imageEncodeFailed"
        case .targetUnsatisfiable:
            return "targetUnsatisfiable"
        case .resourceLimitExceeded:
            return "resourceLimitExceeded"
        }
    }
}
