//
//  CompressionDemoModel.swift
//  WICompressExample
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import Observation
import PhotosUI
import SwiftUI
import WICompress

@MainActor
@Observable
final class CompressionDemoModel {
    enum Mode: String, CaseIterable, Identifiable {
        case process
        case target

        var id: Self { self }

        var title: String {
            switch self {
            case .process:
                "Smart"
            case .target:
                "500 KB Limit"
            }
        }

        var detail: String {
            switch self {
            case .process:
                "Uses the default Luban V2 sizing and quality settings."
            case .target:
                "Searches for the best result that does not exceed 500 KB."
            }
        }
    }

    private enum Phase {
        case idle
        case loading
        case ready
        case processing
    }

    var selectedItem: PhotosPickerItem?
    var mode: Mode = .process

    private(set) var source: ExampleImage?
    private(set) var result: ExampleImage?
    private(set) var errorMessage: String?

    @ObservationIgnored
    private var loadTask: Task<Void, Never>?
    @ObservationIgnored
    private var compressionTask: Task<Void, Never>?
    private var phase: Phase = .idle

    var isLoading: Bool {
        phase == .loading
    }

    var isProcessing: Bool {
        phase == .processing
    }

    func loadSelection() {
        loadTask?.cancel()
        compressionTask?.cancel()

        source = nil
        result = nil
        errorMessage = nil

        guard let selectedItem else {
            phase = .idle
            return
        }

        phase = .loading
        loadTask = Task { [weak self, selectedItem] in
            guard let self else { return }

            do {
                guard let data = try await selectedItem.loadTransferable(type: Data.self) else {
                    throw ExampleError.imageDataUnavailable
                }

                try Task.checkCancellation()
                let content = try await ExampleImage.prepareSource(data)
                try Task.checkCancellation()

                self.source = ExampleImage(content)
                self.phase = .ready
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .idle
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func modeDidChange() {
        cancelCompression()
        result = nil
        errorMessage = nil
    }

    func compress() {
        guard let source else { return }

        compressionTask?.cancel()
        result = nil
        errorMessage = nil
        phase = .processing

        let mode = mode
        compressionTask = Task { [weak self, data = source.data] in
            guard let self else { return }

            do {
                let result = try await Self.compress(data, using: mode)
                try Task.checkCancellation()
                let content = try await ExampleImage.prepareResult(result)
                try Task.checkCancellation()

                self.result = ExampleImage(content)
                self.phase = .ready
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .ready
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelCompression() {
        compressionTask?.cancel()
        compressionTask = nil

        if source != nil {
            phase = .ready
        }
    }

    func cancelAll() {
        loadTask?.cancel()
        compressionTask?.cancel()
    }

    private static func compress(
        _ data: Data,
        using mode: Mode
    ) async throws -> WIResult {
        switch mode {
        case .process:
            return try await WICompressor.process(data)
        case .target:
            let target = try WICompressionTarget(maxBytes: 500_000)
            return try await WICompressor.compress(data, to: target)
        }
    }
}

private enum ExampleError: LocalizedError {
    case imageDataUnavailable

    var errorDescription: String? {
        "The selected image could not be loaded."
    }
}
