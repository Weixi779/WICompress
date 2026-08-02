//
//  BenchmarkReport.swift
//  TargetCompressionBenchmark
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WICompress

struct BenchmarkReport: Codable {
    let schemaVersion: Int
    let createdAt: String
    let strategyID: String
    let qualityProtocolID: String
    let environment: BenchmarkEnvironment
    let runs: Int
    let warmupRuns: Int
    let cases: [BenchmarkCaseReport]

    var hasFailures: Bool {
        cases.contains { $0.status != .passed }
    }

    func printSummary() {
        print(
            "\nfixture\trepresentation\tbudget\tstatus\tbytes\tbpp\tutilization"
                + "\tpixels\tarea\tPSNR\tSSIM\tmedian ms"
        )
        for item in cases {
            print(item.summaryLine)
            if let error = item.errorDescription {
                print("  error: \(error)")
            }
        }
    }

    func write(to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

struct BenchmarkEnvironment: Codable {
    let operatingSystem: String
    let architecture: String
    let processorCount: Int
    let processor: String?
    let swiftVersion: String?
    let buildConfiguration: String
    let revision: String?
    let isDirty: Bool?
    let sourceFingerprint: String?

    static var current: Self {
        let repository = BenchmarkCorpus.packageRootURL()
        let status = commandOutput(
            executable: "/usr/bin/git",
            arguments: ["status", "--porcelain"],
            currentDirectory: repository
        )

        return Self(
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            processorCount: ProcessInfo.processInfo.processorCount,
            processor: commandOutput(
                executable: "/usr/sbin/sysctl",
                arguments: ["-n", "machdep.cpu.brand_string"]
            ),
            swiftVersion: commandOutput(
                executable: "/usr/bin/xcrun",
                arguments: ["swift", "--version"]
            ),
            buildConfiguration: currentBuildConfiguration,
            revision: commandOutput(
                executable: "/usr/bin/git",
                arguments: ["rev-parse", "HEAD"],
                currentDirectory: repository
            ),
            isDirty: status.map { !$0.isEmpty },
            sourceFingerprint: sourceFingerprint(in: repository)
        )
    }

    private static func sourceFingerprint(in repository: URL) -> String? {
        let relativePaths = [
            "Package.swift",
            "Sources",
            "benchmarks/target-compression/Sources",
        ]
        let fileManager = FileManager.default
        var files: [URL] = []

        for relativePath in relativePaths {
            let url = repository.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return nil
            }
            if !isDirectory.boolValue {
                files.append(url)
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }
            for case let fileURL as URL in enumerator {
                guard
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                    values.isRegularFile == true
                else {
                    continue
                }
                files.append(fileURL)
            }
        }

        var source = Data()
        for fileURL in files.sorted(by: { $0.path < $1.path }) {
            guard let data = try? Data(contentsOf: fileURL) else {
                return nil
            }
            let path = fileURL.path.replacingOccurrences(
                of: repository.path + "/",
                with: ""
            )
            append(path.data(using: .utf8) ?? Data(), to: &source)
            append(data, to: &source)
        }
        return source.sha256
    }

    private static func append(_ value: Data, to data: inout Data) {
        var count = UInt64(value.count).bigEndian
        withUnsafeBytes(of: &count) { bytes in
            data.append(contentsOf: bytes)
        }
        data.append(value)
    }
}

struct BenchmarkCaseReport: Codable {
    let fixture: String
    let fixtureID: String
    let sourceFormat: String
    let sourceByteCount: Int
    let sourceWidth: Int
    let sourceHeight: Int
    let requestedRepresentation: String
    let budget: BenchmarkBudgetReport
    let status: BenchmarkCaseStatus
    let output: BenchmarkOutputReport?
    let warmupFailure: BenchmarkWarmupFailure?
    let qualityFailure: BenchmarkQualityFailure?
    let artifactFileName: String?
    let hardLimitSatisfied: Bool?
    let stableOutputSignature: Bool?
    let byteUtilization: Double?
    let actualBitsPerPixel: Double?
    let pixelAreaRatio: Double?
    let quality: BenchmarkQualityReport?
    let medianNanoseconds: UInt64?
    let runs: [BenchmarkRunReport]

    init(
        fixture: BenchmarkFixture,
        representation: BenchmarkRepresentation,
        budget: BenchmarkBudget,
        targetByteCount: Int,
        status: BenchmarkCaseStatus,
        warmupFailure: BenchmarkWarmupFailure?,
        qualityFailure: BenchmarkQualityFailure?,
        artifactFileName: String?,
        quality: BenchmarkQualityReport?,
        runs: [BenchmarkRunReport]
    ) {
        let outputs = runs.compactMap(\.output)
        let stableOutputSignature = outputs.isEmpty
            ? nil
            : outputs.count == runs.count
                && outputs.dropFirst().allSatisfy { $0 == outputs.first }
        let hardLimitSatisfied: Bool?
        if runs.contains(where: { $0.errorCode == "hardLimitViolation" }) {
            hardLimitSatisfied = false
        } else {
            hardLimitSatisfied = outputs.isEmpty
                ? nil
                : outputs.allSatisfy { $0.byteCount <= targetByteCount }
        }
        let representativeOutput = stableOutputSignature == true ? outputs.first : nil

        self.fixture = fixture.relativePath
        self.fixtureID = fixture.sha256
        self.sourceFormat = fixture.descriptor.format.benchmarkName
        self.sourceByteCount = fixture.descriptor.byteCount
        self.sourceWidth = fixture.descriptor.orientedPixelSize.width
        self.sourceHeight = fixture.descriptor.orientedPixelSize.height
        self.requestedRepresentation = representation.rawValue
        self.budget = BenchmarkBudgetReport(
            kind: budget.kind,
            ratio: budget.ratio,
            byteCount: budget.absoluteByteCount,
            bitsPerPixel: budget.bitsPerPixel,
            targetByteCount: targetByteCount
        )
        self.status = status
        self.output = representativeOutput
        self.warmupFailure = warmupFailure
        self.qualityFailure = qualityFailure
        self.artifactFileName = artifactFileName
        self.hardLimitSatisfied = hardLimitSatisfied
        self.stableOutputSignature = stableOutputSignature
        self.byteUtilization = representativeOutput.map {
            Double($0.byteCount) / Double(targetByteCount)
        }
        self.actualBitsPerPixel = representativeOutput.map {
            Double($0.byteCount) * 8 / fixture.sourcePixelArea
        }
        self.pixelAreaRatio = representativeOutput.map {
            let outputArea = Double($0.width) * Double($0.height)
            return outputArea / fixture.sourcePixelArea
        }
        self.quality = representativeOutput == nil ? nil : quality
        self.medianNanoseconds = status == .passed || status == .qualityMeasurementFailed
            ? runs.map(\.durationNanoseconds).median
            : nil
        self.runs = runs
    }

    var errorDescription: String? {
        var errors = Set(
            runs.compactMap(\.errorDescription)
                + [
                    warmupFailure?.errorDescription,
                    qualityFailure?.errorDescription
                ].compactMap { $0 }
        )
        if status == .outputSignatureUnstable {
            errors.insert(outputSignatureSummary)
        }
        return errors.isEmpty ? nil : errors.sorted().joined(separator: " | ")
    }

    private var outputSignatureSummary: String {
        let groups = Dictionary(grouping: runs.compactMap(\.output)) { $0 }
        let descriptions = groups.map { output, occurrences in
            "\(occurrences.count)x \(output.format) \(output.width)x\(output.height) "
                + "\(output.byteCount)B sha256:\(output.sha256.prefix(12))"
        }
        .sorted()
        return "Output signatures differ: " + descriptions.joined(separator: ", ")
    }

    var summaryLine: String {
        let bytes = output.map { String($0.byteCount) } ?? "-"
        let bitsPerPixel = actualBitsPerPixel.map {
            String(format: "%.4f", $0)
        } ?? "-"
        let utilization = byteUtilization.map {
            String(format: "%.3f", $0)
        } ?? "-"
        let pixels = output.map { "\($0.width)x\($0.height)" } ?? "-"
        let area = pixelAreaRatio.map {
            String(format: "%.3f", $0)
        } ?? "-"
        let psnr = quality?.psnrRGBDB.map {
            String(format: "%.3f", $0)
        } ?? (quality?.exactMatch == true ? "exact" : "-")
        let ssim = quality?.ssimLuma.map {
            String(format: "%.5f", $0)
        } ?? "-"
        let milliseconds = medianNanoseconds.map {
            String(format: "%.3f", Double($0) / 1_000_000)
        } ?? "-"

        return "\(fixture)\t\(requestedRepresentation)\t\(budget.displayLabel)\t"
            + "\(status.rawValue)\t\(bytes)\t\(bitsPerPixel)\t\(utilization)\t"
            + "\(pixels)\t\(area)\t\(psnr)\t\(ssim)\t\(milliseconds)"
    }
}

struct BenchmarkBudgetReport: Codable {
    let kind: String
    let ratio: Double?
    let byteCount: Int?
    let bitsPerPixel: Double?
    let targetByteCount: Int

    var displayLabel: String {
        switch kind {
        case "ratio":
            return ratio.map { "ratio-\(String(format: "%.6g", $0))" }
                ?? "ratio-invalid"
        case "bytes":
            return byteCount.map { "bytes-\($0)" } ?? "bytes-invalid"
        case "bpp":
            return bitsPerPixel.map { "bpp-\(String(format: "%.6g", $0))" }
                ?? "bpp-invalid"
        default:
            return "unknown"
        }
    }
}

enum BenchmarkCaseStatus: String, Codable {
    case passed
    case warmupFailed
    case failed
    case mixedOutcome
    case outputSignatureUnstable
    case limitViolation
    case qualityMeasurementFailed

    static func resolve(
        runs: [BenchmarkRunReport],
        targetByteCount: Int
    ) -> Self {
        let outputs = runs.compactMap(\.output)
        let failureCount = runs.count - outputs.count

        if outputs.contains(where: { $0.byteCount > targetByteCount })
            || runs.contains(where: { $0.errorCode == "hardLimitViolation" }) {
            return .limitViolation
        }
        if !outputs.isEmpty, failureCount > 0 {
            return .mixedOutcome
        }
        if outputs.isEmpty {
            return .failed
        }
        if outputs.dropFirst().contains(where: { $0 != outputs.first }) {
            return .outputSignatureUnstable
        }
        return .passed
    }
}

struct BenchmarkRunReport: Codable {
    let index: Int
    let durationNanoseconds: UInt64
    let outcome: BenchmarkRunStatus
    let output: BenchmarkOutputReport?
    let errorCode: String?
    let errorDescription: String?
}

enum BenchmarkRunStatus: String, Codable {
    case success
    case failure
    case validationFailure
}

struct BenchmarkWarmupFailure: Codable {
    let index: Int
    let errorCode: String
    let errorDescription: String
}

struct BenchmarkQualityFailure: Codable {
    let errorCode: String
    let errorDescription: String
}

struct BenchmarkOutputReport: Codable, Hashable {
    let format: String
    let byteCount: Int
    let width: Int
    let height: Int
    let sha256: String

    init(_ result: WIResult, sha256: String) {
        self.format = result.format.benchmarkName
        self.byteCount = result.byteCount
        self.width = result.pixelSize.width
        self.height = result.pixelSize.height
        self.sha256 = sha256
    }
}

extension ImageFormat {
    var benchmarkName: String {
        switch self {
        case .jpeg:
            return "jpeg"
        case .png:
            return "png"
        case .heif:
            return "heif"
        case .unknown:
            return "unknown"
        }
    }
}

private var currentArchitecture: String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "unknown"
    #endif
}

private var currentBuildConfiguration: String {
    #if DEBUG
    return "debug"
    #else
    return "release"
    #endif
}

private func commandOutput(
    executable: String,
    arguments: [String],
    currentDirectory: URL? = nil
) -> String? {
    #if os(macOS)
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
    #else
    return nil
    #endif
}

private extension Array where Element == UInt64 {
    var median: UInt64 {
        guard !isEmpty else {
            return 0
        }

        let values = sorted()
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            let lower = values[middle - 1]
            let upper = values[middle]
            return lower + (upper - lower) / 2
        }
        return values[middle]
    }
}
