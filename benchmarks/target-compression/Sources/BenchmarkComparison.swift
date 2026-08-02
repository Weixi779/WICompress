//
//  BenchmarkComparison.swift
//  TargetCompressionBenchmark
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

struct BenchmarkComparisonConfiguration {
    let baselineURL: URL
    let candidateURL: URL
    let jsonOutputURL: URL?
    let requireIdenticalOutput: Bool

    static let usage = """
    Compare two schema-v2 Target compression benchmark reports.

    Usage:
      swift run -c release TargetCompressionBenchmark compare \
        --baseline <path> --candidate <path> [options]

    Options:
      --baseline <path>             Baseline JSON report.
      --candidate <path>            Candidate JSON report.
      --json <path>                 Write the structured comparison as JSON.
      --require-identical-output    Require identical status and output signature.
      --help                        Show this help.
    """

    static func parse(_ arguments: [String]) throws -> Self {
        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        var baselineURL: URL?
        var candidateURL: URL?
        var jsonOutputURL: URL?
        var requireIdenticalOutput = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--baseline":
                baselineURL = try pathValue(
                    after: argument,
                    arguments: arguments,
                    index: &index,
                    relativeTo: currentDirectory
                )
            case "--candidate":
                candidateURL = try pathValue(
                    after: argument,
                    arguments: arguments,
                    index: &index,
                    relativeTo: currentDirectory
                )
            case "--json":
                jsonOutputURL = try pathValue(
                    after: argument,
                    arguments: arguments,
                    index: &index,
                    relativeTo: currentDirectory
                )
            case "--require-identical-output":
                requireIdenticalOutput = true
            default:
                throw BenchmarkComparisonConfigurationError.unknownArgument(argument)
            }
            index += 1
        }

        guard let baselineURL else {
            throw BenchmarkComparisonConfigurationError.missingOption("--baseline")
        }
        guard let candidateURL else {
            throw BenchmarkComparisonConfigurationError.missingOption("--candidate")
        }
        return Self(
            baselineURL: baselineURL,
            candidateURL: candidateURL,
            jsonOutputURL: jsonOutputURL,
            requireIdenticalOutput: requireIdenticalOutput
        )
    }

    private static func pathValue(
        after option: String,
        arguments: [String],
        index: inout Int,
        relativeTo directory: URL
    ) throws -> URL {
        index += 1
        guard index < arguments.count else {
            throw BenchmarkComparisonConfigurationError.missingValue(option)
        }
        let value = arguments[index]
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        return directory.appendingPathComponent(value)
    }
}

enum BenchmarkComparison {
    static func compare(
        baselineAt baselineURL: URL,
        candidateAt candidateURL: URL,
        requireIdenticalOutput: Bool = false
    ) throws -> BenchmarkComparisonReport {
        let baseline = try decodeReport(at: baselineURL, role: .baseline)
        let candidate = try decodeReport(at: candidateURL, role: .candidate)
        return try compare(
            baseline: baseline,
            candidate: candidate,
            requireIdenticalOutput: requireIdenticalOutput
        )
    }

    static func compare(
        baseline: BenchmarkReport,
        candidate: BenchmarkReport,
        requireIdenticalOutput: Bool = false
    ) throws -> BenchmarkComparisonReport {
        try validateReportCompatibility(
            baseline: baseline,
            candidate: candidate
        )

        let baselineCases = try indexedCases(in: baseline, role: .baseline)
        let candidateCases = try indexedCases(in: candidate, role: .candidate)
        try validateCaseSets(
            baseline: Set(baselineCases.keys),
            candidate: Set(candidateCases.keys)
        )

        let timing = timingAvailability(
            baseline: baseline,
            candidate: candidate
        )
        let cases = baselineCases.keys.sorted().map { key in
            guard
                let baselineCase = baselineCases[key],
                let candidateCase = candidateCases[key]
            else {
                preconditionFailure("Case-set validation must guarantee paired cases.")
            }
            return compare(
                key: key,
                baseline: baselineCase,
                candidate: candidateCase,
                compareTiming: timing.isEnabled
            )
        }

        let identityMismatches = cases
            .filter { $0.status.changed || !$0.outputSignature.isIdentical }
            .map(\.key)

        return BenchmarkComparisonReport(
            schemaVersion: 1,
            baselineStrategyID: baseline.strategyID,
            candidateStrategyID: candidate.strategyID,
            qualityProtocolID: baseline.qualityProtocolID,
            identicalOutput: BenchmarkIdenticalOutputCheck(
                isRequired: requireIdenticalOutput,
                mismatchKeys: identityMismatches
            ),
            timing: timing,
            cases: cases,
            groups: summarize(cases)
        )
    }

    private static func decodeReport(
        at url: URL,
        role: BenchmarkComparisonRole
    ) throws -> BenchmarkReport {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(BenchmarkSchemaEnvelope.self, from: data)
        guard envelope.schemaVersion == 2 else {
            throw BenchmarkComparisonError.unsupportedSchema(
                role: role,
                actual: envelope.schemaVersion
            )
        }
        return try decoder.decode(BenchmarkReport.self, from: data)
    }

    private static func validateReportCompatibility(
        baseline: BenchmarkReport,
        candidate: BenchmarkReport
    ) throws {
        guard baseline.schemaVersion == 2 else {
            throw BenchmarkComparisonError.unsupportedSchema(
                role: .baseline,
                actual: baseline.schemaVersion
            )
        }
        guard candidate.schemaVersion == 2 else {
            throw BenchmarkComparisonError.unsupportedSchema(
                role: .candidate,
                actual: candidate.schemaVersion
            )
        }
        guard baseline.qualityProtocolID == candidate.qualityProtocolID else {
            throw BenchmarkComparisonError.qualityProtocolMismatch(
                baseline: baseline.qualityProtocolID,
                candidate: candidate.qualityProtocolID
            )
        }
        guard baseline.environment.buildConfiguration == candidate.environment.buildConfiguration else {
            throw BenchmarkComparisonError.buildConfigurationMismatch(
                baseline: baseline.environment.buildConfiguration,
                candidate: candidate.environment.buildConfiguration
            )
        }
        guard baseline.environment.operatingSystem == candidate.environment.operatingSystem else {
            throw BenchmarkComparisonError.operatingSystemMismatch(
                baseline: baseline.environment.operatingSystem,
                candidate: candidate.environment.operatingSystem
            )
        }
        guard baseline.environment.architecture == candidate.environment.architecture else {
            throw BenchmarkComparisonError.architectureMismatch(
                baseline: baseline.environment.architecture,
                candidate: candidate.environment.architecture
            )
        }
        try validateEmbeddedQualityProtocols(in: baseline, role: .baseline)
        try validateEmbeddedQualityProtocols(in: candidate, role: .candidate)
    }

    private static func validateEmbeddedQualityProtocols(
        in report: BenchmarkReport,
        role: BenchmarkComparisonRole
    ) throws {
        for item in report.cases {
            guard let actual = item.quality?.protocolID else {
                continue
            }
            guard actual == report.qualityProtocolID else {
                throw BenchmarkComparisonError.embeddedQualityProtocolMismatch(
                    role: role,
                    fixture: item.fixture,
                    expected: report.qualityProtocolID,
                    actual: actual
                )
            }
        }
    }

    private static func indexedCases(
        in report: BenchmarkReport,
        role: BenchmarkComparisonRole
    ) throws -> [BenchmarkComparisonCaseKey: BenchmarkCaseReport] {
        var result: [BenchmarkComparisonCaseKey: BenchmarkCaseReport] = [:]
        result.reserveCapacity(report.cases.count)

        for item in report.cases {
            let key = try BenchmarkComparisonCaseKey(item)
            guard result.updateValue(item, forKey: key) == nil else {
                throw BenchmarkComparisonError.duplicateCase(role: role, key: key)
            }
        }
        return result
    }

    private static func validateCaseSets(
        baseline: Set<BenchmarkComparisonCaseKey>,
        candidate: Set<BenchmarkComparisonCaseKey>
    ) throws {
        guard baseline == candidate else {
            throw BenchmarkComparisonError.caseSetMismatch(
                missingFromCandidate: baseline.subtracting(candidate).sorted(),
                missingFromBaseline: candidate.subtracting(baseline).sorted()
            )
        }
    }

    private static func timingAvailability(
        baseline: BenchmarkReport,
        candidate: BenchmarkReport
    ) -> BenchmarkTimingAvailability {
        var reasons: [BenchmarkTimingDisabledReason] = []
        let baselineEnvironment = baseline.environment
        let candidateEnvironment = candidate.environment

        if baselineEnvironment.processor == nil || candidateEnvironment.processor == nil {
            reasons.append(.processorUnavailable)
        } else if baselineEnvironment.processor != candidateEnvironment.processor {
            reasons.append(.processorMismatch)
        }
        if baselineEnvironment.processorCount != candidateEnvironment.processorCount {
            reasons.append(.processorCountMismatch)
        }
        if baseline.runs != candidate.runs {
            reasons.append(.runCountMismatch)
        }
        if baseline.warmupRuns != candidate.warmupRuns {
            reasons.append(.warmupRunCountMismatch)
        }
        if baselineEnvironment.swiftVersion != candidateEnvironment.swiftVersion {
            reasons.append(.swiftVersionMismatch)
        }
        if baselineEnvironment.isDirty != false || candidateEnvironment.isDirty != false {
            reasons.append(.dirtyWorktree)
        }

        return BenchmarkTimingAvailability(
            isEnabled: reasons.isEmpty,
            disabledReasons: reasons
        )
    }

    private static func compare(
        key: BenchmarkComparisonCaseKey,
        baseline: BenchmarkCaseReport,
        candidate: BenchmarkCaseReport,
        compareTiming: Bool
    ) -> BenchmarkCaseComparison {
        let baselineSignature = baseline.output.map(BenchmarkOutputSignature.init)
        let candidateSignature = candidate.output.map(BenchmarkOutputSignature.init)
        let timing: BenchmarkMetricDelta? = if compareTiming {
            BenchmarkMetricDelta(
                baseline: baseline.medianNanoseconds.map { Double($0) / 1_000_000 },
                candidate: candidate.medianNanoseconds.map { Double($0) / 1_000_000 }
            )
        } else {
            nil
        }

        return BenchmarkCaseComparison(
            key: key,
            fixture: baseline.fixture,
            status: BenchmarkStatusTransition(
                baseline: baseline.status,
                candidate: candidate.status
            ),
            qualityState: BenchmarkQualityStateTransition(
                baseline: BenchmarkQualityState(baseline),
                candidate: BenchmarkQualityState(candidate)
            ),
            outputSignature: BenchmarkOutputSignatureComparison(
                baseline: baselineSignature,
                candidate: candidateSignature,
                isIdentical: baselineSignature != nil && baselineSignature == candidateSignature
            ),
            byteUtilization: BenchmarkMetricDelta(
                baseline: baseline.byteUtilization,
                candidate: candidate.byteUtilization
            ),
            actualBitsPerPixel: BenchmarkMetricDelta(
                baseline: baseline.actualBitsPerPixel,
                candidate: candidate.actualBitsPerPixel
            ),
            pixelAreaRatio: BenchmarkMetricDelta(
                baseline: baseline.pixelAreaRatio,
                candidate: candidate.pixelAreaRatio
            ),
            psnrRGBDB: BenchmarkMetricDelta(
                baseline: baseline.quality?.psnrRGBDB,
                candidate: candidate.quality?.psnrRGBDB,
                policy: .absoluteOnly
            ),
            ssimLuma: BenchmarkMetricDelta(
                baseline: baseline.quality?.ssimLuma,
                candidate: candidate.quality?.ssimLuma,
                policy: .absoluteOnly
            ),
            medianMilliseconds: timing
        )
    }

    private static func summarize(
        _ cases: [BenchmarkCaseComparison]
    ) -> [BenchmarkGroupComparison] {
        let groups = Dictionary(grouping: cases, by: \.groupKey)
        return groups.keys.sorted().compactMap { key in
            guard let items = groups[key] else {
                return nil
            }
            return BenchmarkGroupComparison(
                key: key,
                baselineSuccess: successSummary(items.map(\.status.baseline)),
                candidateSuccess: successSummary(items.map(\.status.candidate)),
                byteUtilization: pairedMedian(
                    items.map(\.byteUtilization),
                    policy: .absoluteAndRelativePercent
                ),
                actualBitsPerPixel: pairedMedian(
                    items.map(\.actualBitsPerPixel),
                    policy: .absoluteAndRelativePercent
                ),
                pixelAreaRatio: pairedMedian(
                    items.map(\.pixelAreaRatio),
                    policy: .absoluteAndRelativePercent
                ),
                psnrRGBDB: pairedMedian(
                    items.map(\.psnrRGBDB),
                    policy: .absoluteOnly
                ),
                ssimLuma: pairedMedian(
                    items.map(\.ssimLuma),
                    policy: .absoluteOnly
                ),
                medianMilliseconds: pairedMedian(
                    items.compactMap(\.medianMilliseconds),
                    policy: .absoluteAndRelativePercent
                )
            )
        }
    }

    private static func successSummary(
        _ statuses: [BenchmarkCaseStatus]
    ) -> BenchmarkSuccessSummary {
        let passed = statuses.filter { $0 == .passed }.count
        return BenchmarkSuccessSummary(
            caseCount: statuses.count,
            passedCount: passed,
            successRate: statuses.isEmpty ? 0 : Double(passed) / Double(statuses.count)
        )
    }

    private static func pairedMedian(
        _ metrics: [BenchmarkMetricDelta],
        policy: BenchmarkMetricDeltaPolicy
    ) -> BenchmarkPairedMedianDelta {
        precondition(metrics.allSatisfy { $0.policy == policy })
        let paired = metrics.filter { $0.absolute != nil }
        return BenchmarkPairedMedianDelta(
            policy: policy,
            pairCount: paired.count,
            absolute: paired.compactMap(\.absolute).benchmarkMedian,
            relativePercent: policy.includesRelativePercent
                ? paired.compactMap(\.relativePercent).benchmarkMedian
                : nil
        )
    }
}

struct BenchmarkComparisonReport: Codable {
    let schemaVersion: Int
    let baselineStrategyID: String
    let candidateStrategyID: String
    let qualityProtocolID: String
    let identicalOutput: BenchmarkIdenticalOutputCheck
    let timing: BenchmarkTimingAvailability
    let cases: [BenchmarkCaseComparison]
    let groups: [BenchmarkGroupComparison]

    func printSummary() {
        print("\n\(baselineStrategyID) -> \(candidateStrategyID)")
        if timing.isEnabled {
            print("timing comparison: enabled")
        } else {
            let reasons = timing.disabledReasons.map(\.rawValue).joined(separator: ", ")
            print("timing comparison: disabled (\(reasons))")
        }
        if identicalOutput.isRequired || !identicalOutput.isSatisfied {
            let requirement = identicalOutput.isRequired ? "required" : "observed"
            print(
                "identical output: \(requirement), "
                    + "\(identicalOutput.mismatchCount) mismatch(es)"
            )
            for key in identicalOutput.mismatchKeys {
                print("  mismatch: \(key.displayLabel)")
            }
        }
        print("\nrepresentation\tbudget\tbaseline pass\tcandidate pass\tarea Δ\tPSNR Δ\tSSIM Δ\ttime Δ ms")
        for group in groups {
            print(group.summaryLine)
        }
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

struct BenchmarkCaseComparison: Codable {
    let key: BenchmarkComparisonCaseKey
    let fixture: String
    let status: BenchmarkStatusTransition
    let qualityState: BenchmarkQualityStateTransition
    let outputSignature: BenchmarkOutputSignatureComparison
    let byteUtilization: BenchmarkMetricDelta
    let actualBitsPerPixel: BenchmarkMetricDelta
    let pixelAreaRatio: BenchmarkMetricDelta
    let psnrRGBDB: BenchmarkMetricDelta
    let ssimLuma: BenchmarkMetricDelta
    let medianMilliseconds: BenchmarkMetricDelta?

    fileprivate var groupKey: BenchmarkComparisonGroupKey {
        BenchmarkComparisonGroupKey(
            requestedRepresentation: key.requestedRepresentation,
            budget: key.budget
        )
    }
}

struct BenchmarkComparisonCaseKey: Codable, Hashable, Comparable {
    let fixture: String
    let fixtureID: String
    let requestedRepresentation: String
    let budget: BenchmarkComparisonBudgetKey
    let resolvedTargetByteCount: Int

    fileprivate init(_ item: BenchmarkCaseReport) throws {
        self.fixture = item.fixture
        self.fixtureID = item.fixtureID
        self.requestedRepresentation = item.requestedRepresentation
        self.budget = try BenchmarkComparisonBudgetKey(item.budget)
        self.resolvedTargetByteCount = item.budget.targetByteCount
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.fixture != rhs.fixture {
            return lhs.fixture < rhs.fixture
        }
        if lhs.fixtureID != rhs.fixtureID {
            return lhs.fixtureID < rhs.fixtureID
        }
        if lhs.requestedRepresentation != rhs.requestedRepresentation {
            return lhs.requestedRepresentation < rhs.requestedRepresentation
        }
        if lhs.budget != rhs.budget {
            return lhs.budget < rhs.budget
        }
        return lhs.resolvedTargetByteCount < rhs.resolvedTargetByteCount
    }
}

struct BenchmarkComparisonGroupKey: Codable, Hashable, Comparable {
    let requestedRepresentation: String
    let budget: BenchmarkComparisonBudgetKey

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.requestedRepresentation != rhs.requestedRepresentation {
            return lhs.requestedRepresentation < rhs.requestedRepresentation
        }
        return lhs.budget < rhs.budget
    }
}

struct BenchmarkComparisonBudgetKey: Codable, Hashable, Comparable {
    let kind: String
    let value: String
    let displayLabel: String

    fileprivate init(_ budget: BenchmarkBudgetReport) throws {
        self.kind = budget.kind
        self.displayLabel = budget.displayLabel
        switch budget.kind {
        case "ratio":
            guard let value = budget.ratio, value.isFinite else {
                throw BenchmarkComparisonError.invalidBudget(kind: budget.kind)
            }
            self.value = Self.stableDouble(value)
        case "bytes":
            guard let value = budget.byteCount else {
                throw BenchmarkComparisonError.invalidBudget(kind: budget.kind)
            }
            self.value = "integer:\(value)"
        case "bpp":
            guard let value = budget.bitsPerPixel, value.isFinite else {
                throw BenchmarkComparisonError.invalidBudget(kind: budget.kind)
            }
            self.value = Self.stableDouble(value)
        default:
            throw BenchmarkComparisonError.invalidBudget(kind: budget.kind)
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        if lhs.value != rhs.value {
            return lhs.value < rhs.value
        }
        return lhs.displayLabel < rhs.displayLabel
    }

    private static func stableDouble(_ value: Double) -> String {
        "binary64:\(String(value.bitPattern, radix: 16))"
    }
}

struct BenchmarkStatusTransition: Codable {
    let baseline: BenchmarkCaseStatus
    let candidate: BenchmarkCaseStatus
    let changed: Bool

    init(baseline: BenchmarkCaseStatus, candidate: BenchmarkCaseStatus) {
        self.baseline = baseline
        self.candidate = candidate
        self.changed = baseline != candidate
    }
}

struct BenchmarkQualityStateTransition: Codable {
    let baseline: BenchmarkQualityState
    let candidate: BenchmarkQualityState
    let changed: Bool

    init(baseline: BenchmarkQualityState, candidate: BenchmarkQualityState) {
        self.baseline = baseline
        self.candidate = candidate
        self.changed = baseline != candidate
    }
}

struct BenchmarkQualityState: Codable, Equatable {
    let kind: BenchmarkQualityStateKind
    let unavailableReason: String?
    let failureCode: String?
    let failureDescription: String?

    fileprivate init(_ item: BenchmarkCaseReport) {
        if let failure = item.qualityFailure {
            self.kind = .failed
            self.unavailableReason = nil
            self.failureCode = failure.errorCode
            self.failureDescription = failure.errorDescription
        } else if let quality = item.quality, let reason = quality.unavailableReason {
            self.kind = .unavailable
            self.unavailableReason = reason.rawValue
            self.failureCode = nil
            self.failureDescription = nil
        } else if item.quality?.exactMatch == true {
            self.kind = .exactMatch
            self.unavailableReason = nil
            self.failureCode = nil
            self.failureDescription = nil
        } else if item.quality != nil {
            self.kind = .measured
            self.unavailableReason = nil
            self.failureCode = nil
            self.failureDescription = nil
        } else {
            self.kind = .missing
            self.unavailableReason = nil
            self.failureCode = nil
            self.failureDescription = nil
        }
    }
}

enum BenchmarkQualityStateKind: String, Codable, Equatable {
    case measured
    case exactMatch
    case unavailable
    case failed
    case missing
}

struct BenchmarkOutputSignatureComparison: Codable {
    let baseline: BenchmarkOutputSignature?
    let candidate: BenchmarkOutputSignature?
    let isIdentical: Bool
}

struct BenchmarkOutputSignature: Codable, Equatable {
    let format: String
    let byteCount: Int
    let width: Int
    let height: Int
    let sha256: String

    fileprivate init(_ output: BenchmarkOutputReport) {
        self.format = output.format
        self.byteCount = output.byteCount
        self.width = output.width
        self.height = output.height
        self.sha256 = output.sha256
    }
}

struct BenchmarkMetricDelta: Codable {
    let policy: BenchmarkMetricDeltaPolicy
    let baseline: Double?
    let candidate: Double?
    let absolute: Double?
    let relativePercent: Double?

    init(
        baseline: Double?,
        candidate: Double?,
        policy: BenchmarkMetricDeltaPolicy = .absoluteAndRelativePercent
    ) {
        self.policy = policy
        self.baseline = baseline
        self.candidate = candidate

        guard let baseline, let candidate else {
            self.absolute = nil
            self.relativePercent = nil
            return
        }

        let absolute = candidate - baseline
        self.absolute = absolute
        self.relativePercent = !policy.includesRelativePercent || baseline == 0
            ? nil
            : absolute / baseline * 100
    }
}

enum BenchmarkMetricDeltaPolicy: String, Codable, Equatable {
    case absoluteAndRelativePercent
    case absoluteOnly

    fileprivate var includesRelativePercent: Bool {
        self == .absoluteAndRelativePercent
    }
}

struct BenchmarkGroupComparison: Codable {
    let key: BenchmarkComparisonGroupKey
    let baselineSuccess: BenchmarkSuccessSummary
    let candidateSuccess: BenchmarkSuccessSummary
    let byteUtilization: BenchmarkPairedMedianDelta
    let actualBitsPerPixel: BenchmarkPairedMedianDelta
    let pixelAreaRatio: BenchmarkPairedMedianDelta
    let psnrRGBDB: BenchmarkPairedMedianDelta
    let ssimLuma: BenchmarkPairedMedianDelta
    let medianMilliseconds: BenchmarkPairedMedianDelta
}

struct BenchmarkSuccessSummary: Codable {
    let caseCount: Int
    let passedCount: Int
    let successRate: Double
}

struct BenchmarkPairedMedianDelta: Codable {
    let policy: BenchmarkMetricDeltaPolicy
    let pairCount: Int
    let absolute: Double?
    let relativePercent: Double?
}

struct BenchmarkIdenticalOutputCheck: Codable {
    let isRequired: Bool
    let isSatisfied: Bool
    let mismatchCount: Int
    let mismatchKeys: [BenchmarkComparisonCaseKey]

    init(
        isRequired: Bool,
        mismatchKeys: [BenchmarkComparisonCaseKey]
    ) {
        self.isRequired = isRequired
        self.isSatisfied = mismatchKeys.isEmpty
        self.mismatchCount = mismatchKeys.count
        self.mismatchKeys = mismatchKeys
    }
}

struct BenchmarkTimingAvailability: Codable {
    let isEnabled: Bool
    let disabledReasons: [BenchmarkTimingDisabledReason]
}

enum BenchmarkTimingDisabledReason: String, Codable {
    case processorUnavailable
    case processorMismatch
    case processorCountMismatch
    case runCountMismatch
    case warmupRunCountMismatch
    case swiftVersionMismatch
    case dirtyWorktree
}

enum BenchmarkComparisonRole: String, Codable {
    case baseline
    case candidate
}

private struct BenchmarkSchemaEnvelope: Decodable {
    let schemaVersion: Int
}

enum BenchmarkComparisonError: Error, LocalizedError {
    case unsupportedSchema(role: BenchmarkComparisonRole, actual: Int)
    case duplicateCase(role: BenchmarkComparisonRole, key: BenchmarkComparisonCaseKey)
    case caseSetMismatch(
        missingFromCandidate: [BenchmarkComparisonCaseKey],
        missingFromBaseline: [BenchmarkComparisonCaseKey]
    )
    case qualityProtocolMismatch(baseline: String, candidate: String)
    case buildConfigurationMismatch(baseline: String, candidate: String)
    case operatingSystemMismatch(baseline: String, candidate: String)
    case architectureMismatch(baseline: String, candidate: String)
    case embeddedQualityProtocolMismatch(
        role: BenchmarkComparisonRole,
        fixture: String,
        expected: String,
        actual: String
    )
    case invalidBudget(kind: String)
    case outputSignatureMismatch([BenchmarkComparisonCaseKey])

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let role, let actual):
            return "The \(role.rawValue) report uses schema v\(actual); comparison requires v2."
        case .duplicateCase(let role, let key):
            return "The \(role.rawValue) report contains duplicate case: \(key.displayLabel)."
        case .caseSetMismatch(let missingFromCandidate, let missingFromBaseline):
            return "Report case sets differ: \(missingFromCandidate.count) missing from candidate, "
                + "\(missingFromBaseline.count) missing from baseline."
        case .qualityProtocolMismatch(let baseline, let candidate):
            return "Quality protocols differ: \(baseline) versus \(candidate)."
        case .buildConfigurationMismatch(let baseline, let candidate):
            return "Build configurations differ: \(baseline) versus \(candidate)."
        case .operatingSystemMismatch(let baseline, let candidate):
            return "Operating systems differ: \(baseline) versus \(candidate)."
        case .architectureMismatch(let baseline, let candidate):
            return "Architectures differ: \(baseline) versus \(candidate)."
        case .embeddedQualityProtocolMismatch(let role, let fixture, let expected, let actual):
            return "The \(role.rawValue) report embeds quality protocol \(actual) for \(fixture); "
                + "expected \(expected)."
        case .invalidBudget(let kind):
            return "A benchmark case has an invalid \(kind) budget."
        case .outputSignatureMismatch(let cases):
            return "Output identity was required, but \(cases.count) paired case(s) differ."
        }
    }
}

private extension BenchmarkComparisonCaseKey {
    var displayLabel: String {
        "\(fixture)/\(fixtureID.prefix(12))/\(requestedRepresentation)/\(budget.displayLabel)"
            + "/\(resolvedTargetByteCount)B"
    }
}

private extension BenchmarkGroupComparison {
    var summaryLine: String {
        let baselinePass = "\(baselineSuccess.passedCount)/\(baselineSuccess.caseCount)"
        let candidatePass = "\(candidateSuccess.passedCount)/\(candidateSuccess.caseCount)"
        return "\(key.requestedRepresentation)\t\(key.budget.displayLabel)\t"
            + "\(baselinePass)\t\(candidatePass)\t"
            + "\(pixelAreaRatio.summaryValue)\t\(psnrRGBDB.summaryValue)\t"
            + "\(ssimLuma.summaryValue)\t\(medianMilliseconds.summaryValue)"
    }
}

private extension BenchmarkPairedMedianDelta {
    var summaryValue: String {
        guard let absolute else {
            return "-"
        }
        return String(format: "%.5f", absolute)
    }
}

private extension Array where Element == Double {
    var benchmarkMedian: Double? {
        guard !isEmpty else {
            return nil
        }

        let values = sorted()
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}

enum BenchmarkComparisonConfigurationError: Error, LocalizedError {
    case missingOption(String)
    case missingValue(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingOption(let option):
            return "Missing required comparison option \(option)."
        case .missingValue(let option):
            return "Missing value after \(option)."
        case .unknownArgument(let argument):
            return "Unknown comparison argument: \(argument)"
        }
    }
}
