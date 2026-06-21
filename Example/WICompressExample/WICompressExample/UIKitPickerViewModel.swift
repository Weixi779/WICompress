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
        
        do {
            let compressedData = try WICompress.compress(
                imageGroup.rawData,
                options: WICompressOptions(quality: .compression(0.7))
            )
            guard let compressedUIImage = UIImage(data: compressedData) else {
                logger.error("Compression output could not be decoded!")
                return
            }

            self.compressedImageGroup = ImageGroup(
                image: compressedUIImage, 
                rawData: compressedData
            )
            logger.info("Compression successful!")
            logger.info("Compressed format: \(self.compressedImageGroup?.format ?? "unknown")")
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
}
