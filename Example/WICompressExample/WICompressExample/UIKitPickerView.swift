//
//  UIKitPickerView.swift
//  WICompressExample
//
//  Created by 孙世伟 on 2025/7/29.
//

import SwiftUI
import UIKit
import PhotosUI
import WICompress

// Extension to wrap loadObject with async/await
extension NSItemProvider {
    func loadObjectToImage() async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            self.loadObject(ofClass: UIImage.self) { (object, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let image = object as? UIImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: NSError(domain: "LoadObjectError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to cast object to expected type"]))
                }
            }
        }
    }
    
    func loadObjectToData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            self.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "LoadObjectError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to cast object to expected type"]))
                }
            }
        }
    }
}

// PHPickerViewController wrapped in SwiftUI
struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var selectedImageGroup: ImageGroup?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            Task {
                do {
                    async let image = result.itemProvider.loadObjectToImage()
                    async let data = result.itemProvider.loadObjectToData()
                    
                    let loadedImage = try await image
                    let loadedData = try await data
                    
                    await MainActor.run {
                        self.parent.selectedImageGroup = ImageGroup(image: loadedImage, rawData: loadedData)
                    }
                } catch {
                    print("Failed to load image: \(error)")
                }
            }
        }
    }
}

struct UIKitPickerView: View {
    @State var viewModel: UIKitPickerViewModel = .init()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image Selection Button
                Button {
                    viewModel.showImagePicker()
                } label: {
                    Label("Select Image (PHPicker)", systemImage: "photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(10)
                }
                
                if let selectedImageGroup = viewModel.selectedImageGroup {
                    // Original Image Section
                    ImageGroupView(
                        title: "Original Image (PHPicker)",
                        imageGroup: selectedImageGroup,
                        backgroundColor: Color.orange.opacity(0.1)
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
                            title: "Processed Image (PHPicker)",
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
        .sheet(isPresented: $viewModel.isShowingImagePicker) {
            ImagePickerView(selectedImageGroup: $viewModel.selectedImageGroup)
        }
    }
}

#Preview {
    UIKitPickerView()
}
