//
//  FrameGrabView.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import AVKit
import Photos
import PhotosUI
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum BannerState {
    case hidden
    case success
    case denied
    case error
}

struct ShareSheetItem: Identifiable {
    let id = UUID()
    let data: Data
    let format: ImageFormat
    
    var fileExtension: String {
        switch format {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heif: return "heic"
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let item: ShareSheetItem
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Create a temporary file URL for sharing
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("frame_\(UUID().uuidString).\(item.fileExtension)")
        
        try? item.data.write(to: tempURL)
        
        let controller = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        
        controller.completionWithItemsHandler = { _, _, _, _ in
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct FrameGrabView: View {
    let originalURL: URL
    let proxyURL: URL?
    @Binding var selectedVideo: PhotosPickerItem?
    @State private var playerManager: VideoPlayerManager
    @State private var bannerState: BannerState = .hidden
    @State private var displayedMessage: String = ""
    @State private var displayedIsSuccess: Bool = false
    @State private var isSaving = false
    @State private var isZooming = false
    @State private var isScrubbing = false
    @State private var isCarouselScrolling = false
    @State private var showSettings = false
    @State private var shareSheetItem: ShareSheetItem?
    
    // Settings
    @AppStorage("imageFormat") private var imageFormat: String = ImageFormat.jpeg.rawValue
    @AppStorage("includeMetadata") private var includeMetadata: Bool = true
    @AppStorage("sharingAction") private var sharingAction: String = SharingAction.saveToPhotos.rawValue

    init(originalURL: URL, proxyURL: URL?, selectedVideo: Binding<PhotosPickerItem?>) {
        self.originalURL = originalURL
        self.proxyURL = proxyURL
        self._selectedVideo = selectedVideo
        self._playerManager = State(
            initialValue: VideoPlayerManager(originalURL: originalURL, proxyURL: proxyURL)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Video Player Area
                    VideoPlayerSection(
                        playerManager: playerManager,
                        isZooming: $isZooming
                    )

                    Spacer()

                    // Thumbnail Scrubber
                    ThumbnailScrubber(
                        playerManager: playerManager,
                        isScrubbing: $isScrubbing
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .opacity(isZooming ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isZooming)

                    //                // Frame Picker Carousel
                    FramePickerCarousel(
                        playerManager: playerManager,
                        isCarouselScrolling: $isCarouselScrolling,
                        isScrubbing: $isScrubbing
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .opacity(
                        isZooming || isScrubbing || playerManager.isPlaying
                            ? 0 : 1
                    )
                    .animation(.easeInOut(duration: 0.3), value: isZooming)
                    .animation(.easeInOut(duration: 0.3), value: isScrubbing)
                    .animation(
                        .easeInOut(duration: 0.3),
                        value: playerManager.isPlaying
                    )

                    // Bottom Controls
                    FrameControlButtons(
                        playerManager: playerManager,
                        onSaveFrame: {
                            Task {
                                await saveCurrentFrame()
                            }
                        }
                    )
                    .padding(.bottom, 40)
                    .opacity(isZooming || isScrubbing ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isZooming)
                    .animation(.easeInOut(duration: 0.3), value: isScrubbing)
                }

                // Floating Banner
                StatusBanner(
                    message: displayedMessage,
                    isSuccess: displayedIsSuccess
                )
                .opacity(isZooming ? 0 : 1)
                .opacity(bannerState != .hidden ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: isZooming)
                
            }
            .navigationTitle("Framr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        showSettings = true
                    }
                    .opacity(isZooming ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isZooming)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedVideo, matching: .videos) {
                        Label("Photo Library", systemImage: "photo.badge.plus")
                    }
                    .opacity(isZooming ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isZooming)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $shareSheetItem) { item in
                ShareSheet(item: item)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Save Frame Methods

    private func saveCurrentFrame() async {
        isSaving = true
        defer { isSaving = false }

        // Check photo library permission
        let authorizationStatus = PHPhotoLibrary.authorizationStatus(
            for: .addOnly
        )

        switch authorizationStatus {
        case .authorized, .limited:
            await captureAndSaveFrame()
        case .notDetermined:
            // Request permission
            let status = await PHPhotoLibrary.requestAuthorization(
                for: .addOnly
            )
            if status == .authorized || status == .limited {
                await captureAndSaveFrame()
            } else {
                showBanner(state: .denied)
            }
        case .denied, .restricted:
            showBanner(state: .denied)
        @unknown default:
            showBanner(state: .denied)
        }
    }

    private func captureAndSaveFrame() async {
        // Capture the current frame
        guard let frameImage = await playerManager.captureCurrentFrame() else {
            showBanner(state: .error)
            return
        }
        
        // Get cached metadata if enabled (instant - no async needed)
        let imageMetadata = includeMetadata ? playerManager.getImageMetadata() : [:]
        
        // Convert to selected format with metadata
        let format = ImageFormat(rawValue: imageFormat) ?? .jpeg
        guard let imageData = createImageData(from: frameImage, format: format, metadata: imageMetadata) else {
            showBanner(state: .error)
            return
        }
        
        // Handle sharing action
        let action = SharingAction(rawValue: sharingAction) ?? .saveToPhotos
        
        switch action {
        case .saveToPhotos:
            await saveToPhotoLibrary(imageData: imageData, format: format)
        case .shareSheet:
            await MainActor.run {
                shareSheetItem = ShareSheetItem(data: imageData, format: format)
            }
        }
    }
    
    private func createImageData(from image: UIImage, format: ImageFormat, metadata: [String: Any]) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        
        let data = NSMutableData()
        
        let uti: CFString
        switch format {
        case .jpeg:
            uti = UTType.jpeg.identifier as CFString
        case .png:
            uti = UTType.png.identifier as CFString
        case .heif:
            uti = UTType.heic.identifier as CFString
        }
        
        guard let destination = CGImageDestinationCreateWithData(data, uti, 1, nil) else {
            return nil
        }
        
        var options: [String: Any] = [:]
        
        // Merge metadata
        if !metadata.isEmpty {
            for (key, value) in metadata {
                options[key] = value
            }
        }
        
        // Set quality for JPEG
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality as String] = 0.95
        }
        
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return data as Data
    }
    
    private func saveToPhotoLibrary(imageData: Data, format: ImageFormat) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                
                let resourceType: PHAssetResourceType = .photo
                creationRequest.addResource(with: resourceType, data: imageData, options: options)
            }
            
            showBanner(state: .success)
        } catch {
            print("Error saving to photo library: \(error)")
            showBanner(state: .error)
        }
    }

    private func showBanner(state: BannerState) {
        // Update cached content BEFORE showing the banner
        displayedMessage = bannerMessage(for: state)
        displayedIsSuccess = state == .success
        
        withAnimation {
            bannerState = state
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
            withAnimation {
                bannerState = .hidden
                // Don't change displayedMessage or displayedIsSuccess here
                // They stay cached for the fade-out animation
            }
        }
    }

    private func bannerMessage(for state: BannerState) -> String {
        switch state {
        case .success:
            return "Photo successfully saved"
        case .denied:
            return "Photos Library access denied"
        case .error:
            return "Photo couldn't be saved"
        case .hidden:
            return ""
        }
    }
}

#Preview {
    #if DEBUG
        if let url = PreviewHelpers.sampleVideoURL {
            FrameGrabView(originalURL: url, proxyURL: nil, selectedVideo: .constant(nil))
        } else {
            ContentUnavailableView(
                "No Preview Video",
                systemImage: "video.slash",
                description: Text(
                    "Add 'SampleVideo.mp4' to the project bundle to preview"
                )
            )
        }
    #endif
}
