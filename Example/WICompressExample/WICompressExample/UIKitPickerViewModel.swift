//
//  UIKitPickerViewModel.swift
//  WICompressExample
//
//  Created by 孙世伟 on 2025/7/29.
//

import Foundation
import Observation
import SwiftUI
import UIKit
import WICompress
import os

@Observable
final class UIKitPickerViewModel {
    
    @ObservationIgnored
    let logger: Logger = .init(subsystem: "example.uikit", category: "viewModel")
    
    var isShowingImagePicker: Bool = false
    var selectedImageGroup: ImageGroup? {
        didSet {
            // Clear previous compressed result when selection changes
            compressedImageGroup = nil
        }
    }
    var compressedImageGroup: ImageGroup?
    
    func showImagePicker() {
        self.isShowingImagePicker = true
    }
    
    func compressImage() {
        guard let imageGroup = selectedImageGroup else { return }
        
        logger.info("Starting compression...")
        logger.info("Original format: \(imageGroup.format)")
        logger.info("Original file size: \(imageGroup.rawData.count) bytes")
        
        // Log raw data prefix for debugging
        let dataPrefix = imageGroup.rawData.prefix(16)
        let hexString = dataPrefix.map { String(format: "%02x", $0) }.joined(separator: " ")
        logger.info("Raw data prefix: \(hexString)")
        
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
            logger.info("Compressed format: \(self.compressedImageGroup?.format ?? "unknown")")
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
}