//
//  BenchmarkCorpus.swift
//  TargetCompressionBenchmark
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import WICompress
import WIImageIO

struct BenchmarkFixture {
    let url: URL
    let relativePath: String
    let data: Data
    let sha256: String
    let descriptor: ImageDescriptor
    let outputFamily: BenchmarkOutputFamily

    var name: String {
        relativePath
    }
}

enum BenchmarkOutputFamily: String, Codable {
    case jpeg
    case heif
    case png

    var representation: WIImageRepresentation {
        switch self {
        case .jpeg:
            return .jpeg()
        case .heif:
            return .heic
        case .png:
            return .png
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg:
            return "jpg"
        case .heif:
            return "heic"
        case .png:
            return "png"
        }
    }
}

struct BenchmarkCorpus {
    let rootURL: URL
    let urls: [URL]

    private static let supportedExtensions = Set([
        "jpg", "jpeg", "png", "heic", "heif"
    ])

    private static let defaultFixtureNames = [
        "real_jpeg_2098x1350_landscape.jpg",
        "real_heic_4032x3024_o1_gps_hdr.heic",
        "real_png_1086x1630_alpha.png",
        "real_png_814x386_wide.png"
    ]

    static func load(inputURL: URL?) throws -> Self {
        let selection = try inputURL.map(imageSelection) ?? defaultFixtureSelection()
        guard !selection.urls.isEmpty else {
            throw BenchmarkConfigurationError.noSupportedImages(
                inputURL ?? defaultFixtureDirectory()
            )
        }
        return Self(rootURL: selection.rootURL, urls: selection.urls)
    }

    func loadFixture(_ url: URL) throws -> BenchmarkFixture {
        try Self.loadFixture(url, relativeTo: rootURL)
    }

    private static func defaultFixtureSelection() throws -> ImageSelection {
        let directory = defaultFixtureDirectory()
        let urls = try defaultFixtureNames.map { name in
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw BenchmarkConfigurationError.missingDefaultFixture(url)
            }
            return url
        }
        return ImageSelection(rootURL: directory, urls: urls)
    }

    private static func defaultFixtureDirectory() -> URL {
        packageRootURL()
        .appendingPathComponent("Tests/WICompressTests/Resources", isDirectory: true)
    }

    private static func imageSelection(at inputURL: URL) throws -> ImageSelection {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: inputURL.path,
            isDirectory: &isDirectory
        ) else {
            throw BenchmarkConfigurationError.inputNotFound(inputURL)
        }

        if !isDirectory.boolValue {
            guard isSupported(inputURL) else {
                throw BenchmarkConfigurationError.noSupportedImages(inputURL)
            }
            return ImageSelection(
                rootURL: inputURL.deletingLastPathComponent(),
                urls: [inputURL]
            )
        }

        guard let enumerator = FileManager.default.enumerator(
            at: inputURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw BenchmarkConfigurationError.noSupportedImages(inputURL)
        }

        let urls = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, isSupported(url) else {
                return nil
            }
            guard
                let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey]
                ),
                values.isRegularFile == true
            else {
                return nil
            }
            return url
        }
        .sorted { $0.path < $1.path }

        guard !urls.isEmpty else {
            throw BenchmarkConfigurationError.noSupportedImages(inputURL)
        }
        return ImageSelection(rootURL: inputURL, urls: urls)
    }

    private static func loadFixture(
        _ url: URL,
        relativeTo rootURL: URL
    ) throws -> BenchmarkFixture {
        let data = try Data(contentsOf: url)
        let descriptor = try ImageReader.inspect(data)
        let outputFamily: BenchmarkOutputFamily

        switch descriptor.format {
        case .jpeg:
            outputFamily = .jpeg
        case .heif:
            outputFamily = .heif
        case .png:
            outputFamily = .png
        case .unknown:
            throw BenchmarkConfigurationError.noSupportedImages(url)
        }

        return BenchmarkFixture(
            url: url,
            relativePath: relativePath(for: url, rootURL: rootURL),
            data: data,
            sha256: data.sha256,
            descriptor: descriptor,
            outputFamily: outputFamily
        )
    }

    static func packageRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else {
            return url.lastPathComponent
        }
        return String(path.dropFirst(prefix.count))
    }

    private static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

private struct ImageSelection {
    let rootURL: URL
    let urls: [URL]
}
