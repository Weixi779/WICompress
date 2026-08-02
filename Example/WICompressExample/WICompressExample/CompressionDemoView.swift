//
//  CompressionDemoView.swift
//  WICompressExample
//
//  Created by weixi on 2026/8/2.
//  Copyright © 2024 weixi. Licensed under Apache-2.0.
//

import PhotosUI
import SwiftUI

struct CompressionDemoView: View {
    @State private var model = CompressionDemoModel()

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    PhotosPicker(
                        selection: $model.selectedItem,
                        matching: .images,
                        preferredItemEncoding: .current
                    ) {
                        Label("Choose an Image", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if model.isLoading {
                        ProgressView("Reading image…")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if let source = model.source {
                        ImageCard(title: "Original", image: source)
                        CompressionControls(model: model)

                        if let result = model.result {
                            ImageCard(
                                title: "Result",
                                image: result,
                                change: result.byteCountChange(comparedTo: source)
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "No Image Selected",
                            systemImage: "photo",
                            description: Text("Choose a JPEG, PNG, or HEIF image to try WICompress.")
                        )
                        .frame(minHeight: 320)
                    }

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                    }
                }
                .padding()
            }
            .navigationTitle("WICompress")
        }
        .onChange(of: model.selectedItem) {
            model.loadSelection()
        }
        .onChange(of: model.mode) {
            model.modeDidChange()
        }
        .onDisappear {
            model.cancelAll()
        }
    }
}

private struct CompressionControls: View {
    @Bindable var model: CompressionDemoModel

    var body: some View {
        GroupBox("Compression") {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Compression Mode", selection: $model.mode) {
                    ForEach(CompressionDemoModel.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(model.mode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if model.isProcessing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Compressing…")
                        Spacer()
                        Button("Cancel", role: .cancel) {
                            model.cancelCompression()
                        }
                    }
                } else {
                    Button {
                        model.compress()
                    } label: {
                        Label("Compress Image", systemImage: "arrow.down.right.and.arrow.up.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.top, 4)
        }
    }
}

private struct ImageCard: View {
    let title: String
    let image: ExampleImage
    var change: ExampleImage.ByteCountChange?

    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                Image(uiImage: image.preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .background(.quaternary, in: .rect(cornerRadius: 12))
                    .compositingGroup()
                    .clipShape(.rect(cornerRadius: 12))

                VStack(spacing: 8) {
                    LabeledContent("Format", value: image.formattedFormat)
                    LabeledContent("Pixels", value: image.formattedPixelSize)
                    LabeledContent("File Size", value: image.formattedByteCount)

                    if let change {
                        LabeledContent("Change") {
                            Text(change.text)
                                .foregroundStyle(change.color)
                        }
                    }
                }
                .font(.subheadline)
            }
            .padding(.top, 4)
        } label: {
            Text(title)
                .font(.headline)
        }
        .accessibilityElement(children: .contain)
    }
}

private extension ExampleImage.ByteCountChange {
    var color: Color {
        switch self {
        case .smaller:
            .green
        case .unchanged:
            .secondary
        case .larger:
            .orange
        }
    }
}

#Preview {
    CompressionDemoView()
}
