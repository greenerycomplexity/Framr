//
//  SettingsView.swift
//  Framr
//
//  Created by Son Cao on 29/11/25.
//

import SwiftUI

// MARK: - Settings Enums

enum ImageFormat: String, CaseIterable {
    case jpeg = "jpeg"
    case png = "png"
    case heif = "heif"
    
    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heif: return "HEIF"
        }
    }
}

enum SharingAction: String, CaseIterable {
    case saveToPhotos = "saveToPhotos"
    case shareSheet = "shareSheet"
    
    var displayName: String {
        switch self {
        case .saveToPhotos: return "Save to Photos"
        case .shareSheet: return "Open Share Sheet"
        }
    }
    
    var icon: String {
        switch self {
        case .saveToPhotos: return "photo.on.rectangle"
        case .shareSheet: return "square.and.arrow.up"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("imageFormat") private var imageFormat: String = ImageFormat.jpeg.rawValue
    @AppStorage("includeMetadata") private var includeMetadata: Bool = true
    @AppStorage("sharingAction") private var sharingAction: String = SharingAction.saveToPhotos.rawValue
    
    private var selectedFormat: ImageFormat {
        get { ImageFormat(rawValue: imageFormat) ?? .jpeg }
        set { imageFormat = newValue.rawValue }
    }
    
    private var selectedSharingAction: SharingAction {
        SharingAction(rawValue: sharingAction) ?? .saveToPhotos
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Image Format Section
                Section {
                    Picker("Image Format", selection: Binding(
                        get: { ImageFormat(rawValue: imageFormat) ?? .jpeg },
                        set: { imageFormat = $0.rawValue }
                    )) {
                        ForEach(ImageFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                } header: {
                    Text("Output Format")
                } footer: {
                    Text("Choose the image format for saved frames. HEIF offers the best quality-to-size ratio.")
                }
                
                // Metadata Section
                Section {
                    Toggle("Include Metadata", isOn: $includeMetadata)
                } header: {
                    Text("Metadata")
                } footer: {
                    Text("When enabled, saved frames will include available metadata from the original video such as location, camera details, and creation date.")
                }
                
                // Sharing Action Section
                Section {
                    NavigationLink {
                        SharingActionView(selectedAction: Binding(
                            get: { SharingAction(rawValue: sharingAction) ?? .saveToPhotos },
                            set: { sharingAction = $0.rawValue }
                        ))
                    } label: {
                        HStack {
                            Text("Sharing Action")
                            Spacer()
                            Text(selectedSharingAction.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Choose what happens when you save a frame.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SettingsView()
}

