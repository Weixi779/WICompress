//
//  ContentView.swift
//  WICompressExample
//
//  Created by 孙世伟 on 2025/7/28.
//

import SwiftUI
import PhotosUI
import WICompress

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var compressedImage: UIImage?
    @State private var originalImageData: Data?
    @State private var compressedImageData: Data?
    @State private var showingSaveAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                Text("WICompress Test")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // PhotosPicker
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Select Image", systemImage: "photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .onChange(of: selectedItem) { oldValue, newValue in
                    Task {
                        await loadImage()
                    }
                }
                
                if selectedImage != nil {
                    // Original Image Section
                    VStack(spacing: 10) {
                        HStack {
                            Text("Original Image")
                                .font(.headline)
                            Spacer()
                        }
                        
                        if let image = selectedImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(10)
                                .shadow(radius: 2)
                                .onLongPressGesture {
                                    saveImageToPhotos(image)
                                }
                        }
                        
                        // Original Image Info
                        VStack(alignment: .leading, spacing: 5) {
                            if let image = selectedImage {
                                Text("Size: \(Int(image.size.width)) × \(Int(image.size.height))")
                            }
                            if let data = originalImageData {
                                Text("File Size: \(formatFileSize(data.count))")
                                Text("Format: \(getImageFormat(data))")
                                if getImageFormat(data).contains("HEIC") {
                                    Text("📸 Live Photo detected!")
                                        .foregroundColor(.orange)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Compress Button
                    Button("Compress & Fix Orientation") {
                        compressImage()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedImage == nil)
                    
                    // Compressed Image Section
                    if compressedImage != nil {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Processed Image")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            if let image = compressedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 200)
                                    .cornerRadius(10)
                                    .shadow(radius: 2)
                                    .onLongPressGesture {
                                        saveImageToPhotos(image)
                                    }
                            }
                            
                            // Compressed Image Info
                            VStack(alignment: .leading, spacing: 5) {
                                if let image = compressedImage {
                                    Text("Size: \(Int(image.size.width)) × \(Int(image.size.height))")
                                }
                                if let data = compressedImageData {
                                    Text("File Size: \(formatFileSize(data.count))")
                                }
                                if let originalData = originalImageData,
                                   let compressedData = compressedImageData {
                                    let ratio = Double(originalData.count) / Double(compressedData.count)
                                    Text("Compression Ratio: \(String(format: "%.2f", ratio))x")
                                        .foregroundColor(.green)
                                        .fontWeight(.medium)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .alert("Image Saved!", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            Text("The image has been saved to your Photos library.")
        }
    }
    
    @MainActor
    private func loadImage() async {
        guard let selectedItem = selectedItem else { return }
        
        do {
            // Load image data first (for format detection)
            if let data = try await selectedItem.loadTransferable(type: Data.self) {
                originalImageData = data
            }
            
            // Load UIImage
            if let image = try await selectedItem.loadTransferable(type: Image.self) {
                // Convert SwiftUI Image to UIImage (this is a simplified approach)
                // In reality, we should load UIImage directly
                if let data = originalImageData {
                    selectedImage = UIImage(data: data)
                }
            }
        } catch {
            print("Failed to load image: \(error)")
        }
    }
    
    private func compressImage() {
        guard let image = selectedImage else { return }
        
        print("Starting compression...")
        print("Original format: \(getImageFormat(originalImageData ?? Data()))")
        
        // Apply WICompress processing (resize + orientation correction + compression)
        if let data = WICompress.compressImage(image, quality: 0.7, formatData: originalImageData) {
            compressedImageData = data
            compressedImage = UIImage(data: data)
            print("Compression successful!")
        } else {
            print("Compression failed!")
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func getImageFormat(_ data: Data) -> String {
        let format = WIImageFormat(data: data)
        switch format {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heif: return "HEIC/HEIF"
        case .unknown: return "Unknown"
        }
    }
    
    private func saveImageToPhotos(_ image: UIImage) {
        // Show haptic feedback immediately
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Save to Photos
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        
        // Show success alert
        showingSaveAlert = true
        
        print("Image saved to Photos!")
    }
}

#Preview {
    ContentView()
}
