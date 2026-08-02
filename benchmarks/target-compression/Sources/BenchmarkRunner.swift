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
        reports.reserveCapacity(
            corpus.urls.count
                * configuration.representations.count
                * configuration.budgets.count
        )

        for url in corpus.urls {
            let fixture = try corpus.loadFixture(url)
            for representation in configuration.representations {
                for budget in configuration.budgets {
                    let targetByteCount = budget.byteCount(
                        for: fixture.descriptor.byteCount,
                        sourcePixelArea: fixture.sourcePixelArea
                    )
                    print(
                        "running: \(fixture.name), \(representation.rawValue), "
                            + "\(budget.label) -> \(targetByteCount) bytes"
                    )
                    reports.append(
                        try run(
                            fixture: fixture,
                            representation: representation,
                            budget: budget,
                            targetByteCount: targetByteCount
                        )
                    )
                }
            }
        }

        return BenchmarkReport(
            schemaVersion: 2,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            strategyID: configuration.strategyID,
            qualityProtocolID: BenchmarkQualityEvaluator.protocolID,
            environment: .current,
            runs: configuration.runs,
            warmupRuns: configuration.warmupRuns,
            cases: reports
        )
    }

    private func run(
        fixture: BenchmarkFixture,
        representation: BenchmarkRepresentation,
        budget: BenchmarkBudget,
        targetByteCount: Int
    ) throws -> BenchmarkCaseReport {
        let target = try WICompressionTarget(
            maxBytes: targetByteCount,
            sizing: .original,
            output: WIImageOutput(
                representation: representation.representation,
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
                representation: representation,
                budget: budget,
                targetByteCount: targetByteCount,
                status: .warmupFailed,
                warmupFailure: warmupFailure,
                qualityFailure: nil,
                artifactFileName: nil,
                quality: nil,
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
                        representation: representation,
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

        let compressionStatus = BenchmarkCaseStatus.resolve(
            runs: runs,
            targetByteCount: targetByteCount
        )
        let qualityMeasurement: BenchmarkQualityMeasurement?
        if compressionStatus == .passed, let representativeData {
            qualityMeasurement = measureQuality(
                sourceData: fixture.data,
                outputData: representativeData
            )
        } else {
            qualityMeasurement = nil
        }
        let status: BenchmarkCaseStatus = qualityMeasurement?.failure == nil
            ? compressionStatus
            : .qualityMeasurementFailed
        let artifactFileName: String?
        if compressionStatus == .passed, let representativeData {
            artifactFileName = try writeArtifact(
                representativeData,
                fixture: fixture,
                representation: representation,
                budget: budget,
                targetByteCount: targetByteCount
            )
        } else {
            artifactFileName = nil
        }

        return BenchmarkCaseReport(
            fixture: fixture,
            representation: representation,
            budget: budget,
            targetByteCount: targetByteCount,
            status: status,
            warmupFailure: nil,
            qualityFailure: qualityMeasurement?.failure,
            artifactFileName: artifactFileName,
            quality: qualityMeasurement?.report,
            runs: runs
        )
    }

    private func measureQuality(
        sourceData: Data,
        outputData: Data
    ) -> BenchmarkQualityMeasurement {
        do {
            return BenchmarkQualityMeasurement(
                report: try BenchmarkQualityEvaluator.evaluate(
                    sourceData: sourceData,
                    outputData: outputData
                ),
                failure: nil
            )
        } catch let error as BenchmarkQualityError {
            return BenchmarkQualityMeasurement(
                report: nil,
                failure: BenchmarkQualityFailure(
                    errorCode: error.rawValue,
                    errorDescription: error.localizedDescription
                )
            )
        } catch {
            return BenchmarkQualityMeasurement(
                report: nil,
                failure: BenchmarkQualityFailure(
                    errorCode: "qualityMeasurementFailed",
                    errorDescription: error.localizedDescription
                )
            )
        }
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
        representation: BenchmarkRepresentation,
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
        guard !BenchmarkMetadataValidation.sourceMetadataWasRetained(
            in: result.data,
            descriptor: descriptor
        ) else {
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
        guard descriptor.format == representation.imageFormat else {
            throw BenchmarkValidationError.unexpectedOutputRepresentation
        }

        return BenchmarkOutputReport(
            result,
            sha256: result.data.sha256
        )
    }

    private func prepareArtifactDirectory() throws {
        guard let directory = artifactOutputDirectoryURL else {
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
        representation: BenchmarkRepresentation,
        budget: BenchmarkBudget,
        targetByteCount: Int
    ) throws -> String? {
        guard let directory = artifactOutputDirectoryURL else {
            return nil
        }

        let sourceName = fixture.url.deletingPathExtension().lastPathComponent
        let sourceID = fixture.sha256.prefix(12)
        let budgetName = budget.label.replacingOccurrences(of: ".", with: "_")
        let fileName = "\(sourceName)--\(sourceID)--\(representation.rawValue)"
            + "--\(budgetName)--\(budget.artifactIdentity)--\(targetByteCount)"
            + ".\(representation.fileExtension)"
        try data.write(
            to: directory.appendingPathComponent(fileName),
            options: .atomic
        )
        return "\(directory.lastPathComponent)/\(fileName)"
    }

    private var artifactOutputDirectoryURL: URL? {
        configuration.artifactDirectoryURL?.appendingPathComponent(
            configuration.strategyID.benchmarkPathComponent,
            isDirectory: true
        )
    }
}

private struct BenchmarkQualityMeasurement {
    let report: BenchmarkQualityReport?
    let failure: BenchmarkQualityFailure?
}

private extension String {
    var benchmarkPathComponent: String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        var sanitized = ""
        var previousWasSeparator = false

        for scalar in unicodeScalars {
            if allowed.contains(scalar) {
                sanitized.append(String(scalar))
                previousWasSeparator = false
            } else if !previousWasSeparator {
                sanitized.append("-")
                previousWasSeparator = true
            }
        }

        sanitized = sanitized.trimmingCharacters(
            in: CharacterSet(charactersIn: "-_")
        )
        let readablePrefix = String(sanitized.prefix(64))
        guard !readablePrefix.isEmpty else {
            return "strategy--\(Data(utf8).sha256.prefix(12))"
        }
        guard sanitized == self, sanitized.count <= 64 else {
            return "\(readablePrefix)--\(Data(utf8).sha256.prefix(12))"
        }
        return readablePrefix
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
    case unexpectedOutputRepresentation

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
            return "Benchmark output retained source-carried metadata."
        case .unexpectedOutputRepresentation:
            return "Benchmark output does not match the requested representation."
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
