//
//  main.swift
//  TargetCompressionBenchmark
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Darwin
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    try runCommand(arguments: arguments)
} catch {
    fflush(nil)
    let message = "error: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}

private func runCommand(arguments: [String]) throws {
    if arguments.first == "compare" {
        try compareReports(arguments: Array(arguments.dropFirst()))
        return
    }
    try runBenchmark(arguments: arguments)
}

private func runBenchmark(arguments: [String]) throws {
    if arguments.contains("--help") || arguments.contains("-h") {
        print(BenchmarkConfiguration.usage)
        return
    }

    let configuration = try BenchmarkConfiguration.parse(arguments)
    let report = try BenchmarkRunner(configuration: configuration).run()
    report.printSummary()

    if let outputURL = configuration.jsonOutputURL {
        try report.write(to: outputURL)
        print("\nJSON report: \(outputURL.path)")
    }

    if report.hasFailures {
        throw BenchmarkExecutionError.failedCases(
            report.cases.filter { $0.status != .passed }.count
        )
    }
}

private func compareReports(arguments: [String]) throws {
    if arguments.contains("--help") || arguments.contains("-h") {
        print(BenchmarkComparisonConfiguration.usage)
        return
    }

    let configuration = try BenchmarkComparisonConfiguration.parse(arguments)
    let report = try BenchmarkComparison.compare(
        baselineAt: configuration.baselineURL,
        candidateAt: configuration.candidateURL,
        requireIdenticalOutput: configuration.requireIdenticalOutput
    )
    report.printSummary()

    if let outputURL = configuration.jsonOutputURL {
        try report.write(to: outputURL)
        print("\nComparison JSON: \(outputURL.path)")
    }

    if configuration.requireIdenticalOutput, !report.identicalOutput.isSatisfied {
        throw BenchmarkComparisonError.outputSignatureMismatch(
            report.identicalOutput.mismatchKeys
        )
    }
}

enum BenchmarkExecutionError: Error, LocalizedError {
    case failedCases(Int)

    var errorDescription: String? {
        switch self {
        case .failedCases(let count):
            return "Target compression benchmark found \(count) failed case(s)."
        }
    }
}
