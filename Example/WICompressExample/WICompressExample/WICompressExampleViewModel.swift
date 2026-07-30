//
//  WICompressExampleViewModel.swift
//  WICompressExample
//
//  Created by weixi on 2026/6/22.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import Foundation
import ImageIO
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WICompress
import os

struct ImageGroup {
    var image: UIImage
    var rawData: Data
    var imageFormat: WIImageFormat
    
    // Computed properties for UI display
    var fileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(rawData.count))
    }
    
    var imageSize: String {
        return "\(Int(image.size.width)) × \(Int(image.size.height))"
    }
    
    var format: String {
        switch imageFormat {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heif: return "HEIC/HEIF"
        case .unknown: return "Unknown"
        }
    }
    
    var isLivePhoto: Bool {
        imageFormat.isHEIF
    }
}

enum ExampleImageInspector {
    static func format(of data: Data) -> WIImageFormat {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let typeIdentifier = CGImageSourceGetType(source) as String?,
            let type = UTType(typeIdentifier)
        else {
            return .unknown
        }

        if type.conforms(to: .jpeg) {
            return .jpeg
        }
        if type.conforms(to: .png) {
            return .png
        }
        if type.conforms(to: .heic) || type.conforms(to: .heif) {
            return .heif
        }
        return .unknown
    }
}

@Observable
final class WICompressExampleViewModel {
    
    @ObservationIgnored
    let logger: Logger = .init(subsystem: "example", category: "viewModel")
    
    var isPresentPicker: Bool = false
    var selectedItem: PhotosPickerItem? {
        didSet {
            Task {
                await loadImage()
            }
        }
    }
    
    var selectedImageGroup: ImageGroup?
    var compressedImageGroup: ImageGroup?
    
    func pickerToggle() {
        self.isPresentPicker = true
    }
    
    func compressImage() {
        guard let imageGroup = selectedImageGroup else { return }
        
        logger.info("Starting compression...")
        logger.info("Original format: \(imageGroup.format)")
        
        do {
            let result = try WICompressor.process(
                imageGroup.rawData,
                using: WIImageProcess(quality: 0.7)
            )
            guard let compressedUIImage = UIImage(data: result.data) else {
                logger.error("Compression output could not be decoded!")
                return
            }

            self.compressedImageGroup = ImageGroup(
                image: compressedUIImage,
                rawData: result.data,
                imageFormat: result.format
            )
            logger.info("Compression successful!")
        } catch {
            logger.error("Compression failed: \(error.localizedDescription)")
        }
    }
    
    
    func compressionRatio() -> String? {
        guard let original = selectedImageGroup,
              let compressed = compressedImageGroup else { return nil }
        
        let ratio = Double(original.rawData.count) / Double(compressed.rawData.count)
        return String(format: "%.2f", ratio)
    }
    
    @MainActor
    private func loadImage() async {
        guard let selectedItem = selectedItem else { 
            // Clear compressed image when selection changes
            compressedImageGroup = nil
            return 
        }
        
        do {
            let data = try await selectedItem.loadTransferable(type: Data.self)
            
            if let data = data, let uiImage = UIImage(data: data) {
                self.selectedImageGroup = ImageGroup(
                    image: uiImage,
                    rawData: data,
                    imageFormat: ExampleImageInspector.format(of: data)
                )
                // Clear previous compressed result
                self.compressedImageGroup = nil
            }
        } catch {
            logger.error("Failed to load image: \(error.localizedDescription)")
        }
    }
}
