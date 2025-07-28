//
//  WICompressExampleViewModel.swift
//  WICompressExample
//
//  Created by 孙世伟 on 2025/7/28.
//

import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import WICompress
import os

struct ImageGroup {
    var image: UIImage
    var rawData: Data
    
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
        let wiFormat = WIImageFormat(data: rawData)
        switch wiFormat {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heif: return "HEIC/HEIF"
        case .unknown: return "Unknown"
        }
    }
    
    var isLivePhoto: Bool {
        let wiFormat = WIImageFormat(data: rawData)
        return wiFormat.isHEIF
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
        
        // Apply WICompress processing (resize + orientation correction + compression)
        if let compressedData = WICompress.compressImage(
            imageGroup.image, 
            quality: 0.7, 
            formatData: imageGroup.rawData
        ), let compressedUIImage = UIImage(data: compressedData) {
            
            self.compressedImageGroup = ImageGroup(
                image: compressedUIImage, 
                rawData: compressedData
            )
            logger.info("Compression successful!")
        } else {
            logger.error("Compression failed!")
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
                self.selectedImageGroup = ImageGroup(image: uiImage, rawData: data)
                // Clear previous compressed result
                self.compressedImageGroup = nil
            }
        } catch {
            logger.error("Failed to load image: \(error.localizedDescription)")
        }
    }
}
