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

enum BannerState {
    case hidden
    case success
    case denied
    case error
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
                        // Settings action
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

        // Save to photo library
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: frameImage)
            }

            showBanner(state: .success)
        } catch {
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
