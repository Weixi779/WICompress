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
    let environment: BenchmarkEnvironment
    let runs: Int
    let warmupRuns: Int
    let cases: [BenchmarkCaseReport]

    var hasFailures: Bool {
        cases.contains { $0.status != .passed }
    }

    func printSummary() {
        print("\nfixture\tfamily\tbudget\tstatus\tbytes\tutilization\tpixels\tarea\tmedian ms")
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
            isDirty: status.map { !$0.isEmpty }
        )
    }
}

struct BenchmarkCaseReport: Codable {
    let fixture: String
    let fixtureID: String
    let sourceFormat: String
    let sourceByteCount: Int
    let sourceWidth: Int
    let sourceHeight: Int
    let outputFamily: String
    let budget: BenchmarkBudgetReport
    let status: BenchmarkCaseStatus
    let output: BenchmarkOutputReport?
    let warmupFailure: BenchmarkWarmupFailure?
    let artifactFileName: String?
    let hardLimitSatisfied: Bool?
    let stableOutputSignature: Bool?
    let byteUtilization: Double?
    let pixelAreaRatio: Double?
    let medianNanoseconds: UInt64?
    let runs: [BenchmarkRunReport]

    init(
        fixture: BenchmarkFixture,
        budget: BenchmarkBudget,
        targetByteCount: Int,
        status: BenchmarkCaseStatus,
        warmupFailure: BenchmarkWarmupFailure?,
        artifactFileName: String?,
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
        self.outputFamily = fixture.outputFamily.rawValue
        self.budget = BenchmarkBudgetReport(
            kind: budget.kind,
            ratio: budget.ratio,
            byteCount: budget.absoluteByteCount,
            targetByteCount: targetByteCount
        )
        self.status = status
        self.output = representativeOutput
        self.warmupFailure = warmupFailure
        self.artifactFileName = artifactFileName
        self.hardLimitSatisfied = hardLimitSatisfied
        self.stableOutputSignature = stableOutputSignature
        self.byteUtilization = representativeOutput.map {
            Double($0.byteCount) / Double(targetByteCount)
        }
        self.pixelAreaRatio = representativeOutput.map {
            let outputArea = Double($0.width) * Double($0.height)
            let sourceSize = fixture.descriptor.orientedPixelSize
            let sourceArea = Double(sourceSize.width) * Double(sourceSize.height)
            return outputArea / sourceArea
        }
        self.medianNanoseconds = status == .passed
            ? runs.map(\.durationNanoseconds).median
            : nil
        self.runs = runs
    }

    var errorDescription: String? {
        var errors = Set(
            runs.compactMap(\.errorDescription)
                + [warmupFailure?.errorDescription].compactMap { $0 }
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
        let utilization = byteUtilization.map {
            String(format: "%.3f", $0)
        } ?? "-"
        let pixels = output.map { "\($0.width)x\($0.height)" } ?? "-"
        let area = pixelAreaRatio.map {
            String(format: "%.3f", $0)
        } ?? "-"
        let milliseconds = medianNanoseconds.map {
            String(format: "%.3f", Double($0) / 1_000_000)
        } ?? "-"

        return "\(fixture)\t\(outputFamily)\t\(budget.displayLabel)\t"
            + "\(status.rawValue)\t\(bytes)\t\(utilization)\t\(pixels)\t"
            + "\(area)\t\(milliseconds)"
    }
}

struct BenchmarkBudgetReport: Codable {
    let kind: String
    let ratio: Double?
    let byteCount: Int?
    let targetByteCount: Int

    var displayLabel: String {
        switch kind {
        case "ratio":
            return ratio.map { "ratio-\(String(format: "%.17g", $0))" }
                ?? "ratio-invalid"
        case "bytes":
            return byteCount.map { "bytes-\($0)" } ?? "bytes-invalid"
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
