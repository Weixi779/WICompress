//
//  WICompressExampleView.swift
//  WICompressExample
//
//  Created by 孙世伟 on 2025/7/28.
//

import SwiftUI
import PhotosUI
import WICompress

// Reusable ImageGroupView component
struct ImageGroupView: View {
    let title: String
    let imageGroup: ImageGroup
    let backgroundColor: Color
    let showCompressionRatio: String?
    
    @State private var showSaveSuccess: Bool = false
    
    init(
        title: String,
        imageGroup: ImageGroup,
        backgroundColor: Color = Color.gray.opacity(0.1),
        showCompressionRatio: String? = nil
    ) {
        self.title = title
        self.imageGroup = imageGroup
        self.backgroundColor = backgroundColor
        self.showCompressionRatio = showCompressionRatio
    }
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("Long press to save")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ZStack {
                Image(uiImage: imageGroup.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(10)
                    .shadow(radius: 2)
                    .onLongPressGesture {
                        saveImageToPhotos(imageGroup.image)
                    }
                
                // Save success overlay
                if showSaveSuccess {
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.title)
                                .foregroundColor(.white)
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSaveSuccess)
            
            // Image Info
            VStack(alignment: .leading, spacing: 5) {
                Text("Size: \(imageGroup.imageSize)")
                Text("File Size: \(imageGroup.fileSize)")
                Text("Format: \(imageGroup.format)")
                
                if imageGroup.isLivePhoto {
                    Text("📸 Live Photo detected!")
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                }
                
                if let ratio = showCompressionRatio {
                    Text("Compression Ratio: \(ratio)x")
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(backgroundColor)
            .cornerRadius(8)
        }
    }
    
    private func saveImageToPhotos(_ image: UIImage) {
        // Show haptic feedback immediately
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Save to Photos
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        
        // Show success indicator
        showSaveSuccess = true
        
        // Auto hide after 1 second
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            showSaveSuccess = false
        }
    }
}

struct WICompressExampleView: View {
    @State var viewModel: WICompressExampleViewModel = .init()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                Text("WICompress Test")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Image Selection Button
                Button {
                    viewModel.pickerToggle()
                } label: {
                    Label("Select Image", systemImage: "photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                
                if let selectedImageGroup = viewModel.selectedImageGroup {
                    // Original Image Section
                    ImageGroupView(
                        title: "Original Image",
                        imageGroup: selectedImageGroup,
                        backgroundColor: Color.gray.opacity(0.1)
                    )
                    
                    // Compress Button
                    Button("Compress & Fix Orientation") {
                        viewModel.compressImage()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.selectedImageGroup == nil)
                    
                    // Compressed Image Section
                    if let compressedImageGroup = viewModel.compressedImageGroup {
                        ImageGroupView(
                            title: "Processed Image",
                            imageGroup: compressedImageGroup,
                            backgroundColor: Color.green.opacity(0.1),
                            showCompressionRatio: viewModel.compressionRatio()
                        )
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .photosPicker(
            isPresented: $viewModel.isPresentPicker, 
            selection: $viewModel.selectedItem, 
            matching: .images
        )
    }
}

#Preview {
    WICompressExampleView()
}
