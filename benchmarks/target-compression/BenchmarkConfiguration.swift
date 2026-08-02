//
//  BenchmarkConfiguration.swift
//  TargetCompressionBenchmark
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation

struct BenchmarkConfiguration {
    let inputURL: URL?
    let budgets: [BenchmarkBudget]
    let runs: Int
    let warmupRuns: Int
    let jsonOutputURL: URL?
    let artifactDirectoryURL: URL?

    static let usage = """
    Compare WICompress target compression against a deterministic image corpus.

    Usage:
      swift run -c release TargetCompressionBenchmark [options]

    Options:
      --input <file-or-directory>  Use one image or every supported image in a directory.
      --ratios <values>            Comma-separated source-byte ratios, for example 0.5,0.2.
      --bytes <values>             Comma-separated absolute byte budgets.
      --runs <count>               Timed runs per case. Default: 3.
      --warmup <count>             Untimed warmup runs per case. Default: 1.
      --json <path>                Write the complete report as JSON.
      --artifacts <directory>      Save the first validated output for each passed case.
      --help                       Show this help.

    When --input is omitted, the benchmark uses the repository's four-image smoke corpus.
    When neither --ratios nor --bytes is provided, ratios 0.5 and 0.2 are used.
    """

    static func parse(_ arguments: [String]) throws -> Self {
        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        var inputURL: URL?
        var ratios: [Double] = []
        var byteBudgets: [Int] = []
        var runs = 3
        var warmupRuns = 1
        var jsonOutputURL: URL?
        var artifactDirectoryURL: URL?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--input":
                inputURL = try pathValue(
                    after: argument,
                    arguments: arguments,
                    index: &index,
                    relativeTo: currentDirectory
                )
            case "--ratios":
                ratios = try doubleList(
                    after: argument,
                    arguments: arguments,
                    index: &index
                )
                guard ratios.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1 }) else {
                    throw BenchmarkConfigurationError.invalidValue(argument)
                }
            case "--bytes":
                byteBudgets = try integerList(
                    after: argument,
                    arguments: arguments,
                    index: &index
                )
                guard byteBudgets.allSatisfy({ $0 > 0 }) else {
                    throw BenchmarkConfigurationError.invalidValue(argument)
                }
            case "--runs":
                runs = try integerValue(
                    after: argument,
                    arguments: arguments,
                    index: &index
                )
                guard runs > 0 else {
                    throw BenchmarkConfigurationError.invalidValue(argument)
                }
            case "--warmup":
                warmupRuns = try integerValue(
                    after: argument,
                    arguments: arguments,
                    index: &index
                )
                guard warmupRuns >= 0 else {
                    throw BenchmarkConfigurationError.invalidValue(argument)
                }
            case "--json":
                jsonOutputURL = try pathValue(
                    after: argument,
                    arguments: arguments,
                    index: &index,
                    relativeTo: currentDirectory
                )
            case "--artifacts":
                artifactDirectoryURL = try pathValue(
                    after: argument,
                    arguments: arguments,
                    index: &index,
                    relativeTo: currentDirectory
                )
            default:
                throw BenchmarkConfigurationError.unknownArgument(argument)
            }

            index += 1
        }

        let budgets: [BenchmarkBudget]
        if ratios.isEmpty && byteBudgets.isEmpty {
            budgets = [.ratio(0.5), .ratio(0.2)]
        } else {
            budgets = ratios.map(BenchmarkBudget.ratio)
                + byteBudgets.map(BenchmarkBudget.bytes)
        }

        return Self(
            inputURL: inputURL,
            budgets: budgets,
            runs: runs,
            warmupRuns: warmupRuns,
            jsonOutputURL: jsonOutputURL,
            artifactDirectoryURL: artifactDirectoryURL
        )
    }

    private static func pathValue(
        after option: String,
        arguments: [String],
        index: inout Int,
        relativeTo directory: URL
    ) throws -> URL {
        let value = try stringValue(
            after: option,
            arguments: arguments,
            index: &index
        )
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        return directory.appendingPathComponent(value)
    }

    private static func doubleList(
        after option: String,
        arguments: [String],
        index: inout Int
    ) throws -> [Double] {
        let value = try stringValue(
            after: option,
            arguments: arguments,
            index: &index
        )
        let components = value.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        let values = components.compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        guard !values.isEmpty, values.count == components.count else {
            throw BenchmarkConfigurationError.invalidValue(option)
        }
        return values
    }

    private static func integerList(
        after option: String,
        arguments: [String],
        index: inout Int
    ) throws -> [Int] {
        let value = try stringValue(
            after: option,
            arguments: arguments,
            index: &index
        )
        let components = value.split(
            separator: ",",
            omittingEmptySubsequences: false
        )
        let values = components.compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        guard !values.isEmpty, values.count == components.count else {
            throw BenchmarkConfigurationError.invalidValue(option)
        }
        return values
    }

    private static func integerValue(
        after option: String,
        arguments: [String],
        index: inout Int
    ) throws -> Int {
        let value = try stringValue(
            after: option,
            arguments: arguments,
            index: &index
        )
        guard let value = Int(value) else {
            throw BenchmarkConfigurationError.invalidValue(option)
        }
        return value
    }

    private static func stringValue(
        after option: String,
        arguments: [String],
        index: inout Int
    ) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw BenchmarkConfigurationError.missingValue(option)
        }
        return arguments[index]
    }
}

enum BenchmarkBudget: Sendable {
    case ratio(Double)
    case bytes(Int)

    var label: String {
        switch self {
        case .ratio(let ratio):
            return "ratio-\(String(format: "%.17g", ratio))"
        case .bytes(let bytes):
            return "bytes-\(bytes)"
        }
    }

    var kind: String {
        switch self {
        case .ratio:
            return "ratio"
        case .bytes:
            return "bytes"
        }
    }

    var ratio: Double? {
        guard case .ratio(let ratio) = self else {
            return nil
        }
        return ratio
    }

    var absoluteByteCount: Int? {
        guard case .bytes(let bytes) = self else {
            return nil
        }
        return bytes
    }

    func byteCount(for sourceByteCount: Int) -> Int {
        switch self {
        case .ratio(let ratio):
            let value = Double(sourceByteCount) * ratio
            guard value < Double(Int.max) else {
                return Int.max
            }
            return max(1, Int(value.rounded(.down)))
        case .bytes(let bytes):
            return bytes
        }
    }
}

enum BenchmarkConfigurationError: Error, LocalizedError {
    case inputNotFound(URL)
    case noSupportedImages(URL)
    case missingDefaultFixture(URL)
    case missingValue(String)
    case invalidValue(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .inputNotFound(let url):
            return "Benchmark input does not exist: \(url.path)"
        case .noSupportedImages(let url):
            return "No supported static images were found at: \(url.path)"
        case .missingDefaultFixture(let url):
            return "The default smoke fixture is missing: \(url.path)"
        case .missingValue(let option):
            return "Missing value after \(option)."
        case .invalidValue(let option):
            return "Invalid value for \(option)."
        case .unknownArgument(let argument):
            return "Unknown benchmark argument: \(argument)"
        }
    }
}
