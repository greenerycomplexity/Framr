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

struct FrameGrabView: View {
    let videoURL: URL
    @Binding var selectedVideo: PhotosPickerItem?
    @State private var playerManager: VideoPlayerManager
    @State private var showingBanner = false
    @State private var bannerMessage = ""
    @State private var bannerIsSuccess = true
    @State private var isSaving = false
    @State private var isZooming = false
    @State private var isScrubbing = false
    @State private var isCarouselScrolling = false

    init(videoURL: URL, selectedVideo: Binding<PhotosPickerItem?>) {
        self.videoURL = videoURL
        self._selectedVideo = selectedVideo
        self._playerManager = State(
            initialValue: VideoPlayerManager(url: videoURL)
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                topNavigationBar
                    .opacity(isZooming ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isZooming)

                Spacer()

                // Video Player Area
                VideoPlayerSection(playerManager: playerManager, isZooming: $isZooming)

                Spacer()

                // Thumbnail Scrubber
                ThumbnailScrubber(playerManager: playerManager, isScrubbing: $isScrubbing)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .opacity(isZooming ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isZooming)
                
//                // Frame Picker Carousel
                FramePickerCarousel(playerManager: playerManager, isCarouselScrolling: $isCarouselScrolling, isScrubbing: $isScrubbing)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .opacity(isZooming || isScrubbing ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isZooming)
                    .animation(.easeInOut(duration: 0.3), value: isScrubbing)

                // Bottom Controls
                FrameControlButtons(
                    playerManager: playerManager,
                    isSaving: isSaving,
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
            if showingBanner {
                StatusBanner(
                    message: bannerMessage,
                    isSuccess: bannerIsSuccess,
                    isVisible: $showingBanner
                )
                .opacity(isZooming ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: isZooming)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack {
            // Settings Button
            Button(action: {
                // Settings action
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .glassEffect(
                        .regular.interactive().tint(.white.opacity(0.1))
                    )
            }

            Spacer()

            // Title
            Text("Frame Grabber")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            // Photo Library Button
            PhotosPicker(selection: $selectedVideo, matching: .videos) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .glassEffect(
                        .regular.interactive().tint(.white.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
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
                await showBanner(
                    message: "Photo access denied",
                    isSuccess: false
                )
            }
        case .denied, .restricted:
            await showBanner(message: "Photo access denied", isSuccess: false)
        @unknown default:
            await showBanner(
                message: "Unable to access photos",
                isSuccess: false
            )
        }
    }

    private func captureAndSaveFrame() async {
        // Capture the current frame
        guard let frameImage = await playerManager.captureCurrentFrame() else {
            await showBanner(
                message: "Failed to capture frame",
                isSuccess: false
            )
            return
        }

        // Save to photo library
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: frameImage)
            }

            await showBanner(message: "Frame saved to Photos!", isSuccess: true)
        } catch {
            await showBanner(message: "Failed to save frame", isSuccess: false)
        }
    }

    private func showBanner(message: String, isSuccess: Bool) async {
        await MainActor.run {
            bannerMessage = message
            bannerIsSuccess = isSuccess
            withAnimation {
                showingBanner = true
            }

            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 2 seconds
                withAnimation {
                    showingBanner = false
                }
            }
        }
    }
}

#Preview {
    #if DEBUG
        if let url = PreviewHelpers.sampleVideoURL {
            FrameGrabView(videoURL: url, selectedVideo: .constant(nil))
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
