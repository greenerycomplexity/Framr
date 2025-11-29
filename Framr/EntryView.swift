//
//  EntryView.swift
//  Framr
//
//  Created by Son Cao on 10/11/25.
//

import SwiftUI
import PhotosUI
import AVFoundation

struct EntryView: View {
    @State private var selectedVideo: PhotosPickerItem? = nil
    @State private var videoURL: URL? = nil
    @State private var proxyURL: URL? = nil
    @State private var isProcessing = false
    @State private var processingProgress: Double = 0.0
    @State private var processingMessage: String = ""
    @State private var targetProgress: Double = 0.0
    
    var body: some View {
        ZStack {
            if let videoURL = videoURL, !isProcessing {
                FrameGrabView(
                    originalURL: videoURL,
                    proxyURL: proxyURL,
                    selectedVideo: $selectedVideo
                )
                .id(videoURL)
            }
            else if isProcessing {
                VStack(spacing: 20) {
                    ProgressView(value: processingProgress)
                        .frame(width: 200)
                        .tint(.orange)
                    Text(processingMessage)
                        .font(.headline)
                    Text("\(Int(processingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            else {
                NoVideoView(selectedVideo: $selectedVideo)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: selectedVideo) { oldValue, newValue in
            Task {
                await loadVideo(from: newValue)
            }
        }
    }
    
    private func loadVideo(from item: PhotosPickerItem?) async {
        guard let item = item else {
            videoURL = nil
            proxyURL = nil
            return
        }
        
        // Clear the current video to show loading state
        videoURL = nil
        proxyURL = nil
        isProcessing = true
        processingProgress = 0.0
        targetProgress = 0.0
        processingMessage = "Importing video..."
        
        // Start smooth progress animation task that interpolates towards targetProgress
        let smoothProgressTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    let diff = targetProgress - processingProgress
                    if abs(diff) > 0.001 {
                        // Smoothly interpolate: move 15% of the remaining distance each tick
                        // This creates an easing effect
                        processingProgress += diff * 0.15
                    } else {
                        processingProgress = targetProgress
                    }
                }
                try? await Task.sleep(nanoseconds: 30_000_000) // 0.03 seconds for smooth 30fps
            }
        }
        
        // Start animated target progress for import phase (0-30%)
        // Since loadTransferable doesn't provide progress, we animate smoothly
        let importAnimationTask = Task {
            var progress = 0.0
            while !Task.isCancelled && progress < 0.29 {
                progress += 0.01
                await MainActor.run {
                    self.targetProgress = progress
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        do {
            // Step 1: Load and copy video from Photos (animated 0-30% target progress)
            guard let movie = try await item.loadTransferable(type: VideoFile.self) else {
                importAnimationTask.cancel()
                smoothProgressTask.cancel()
                isProcessing = false
                return
            }
            
            // Stop the import animation - we'll now use real progress
            importAnimationTask.cancel()
            
            videoURL = movie.url
            
            // Step 2: Generate 1080p proxy (30-100% progress)
            // Check if proxy already exists
            if ProxyManager.proxyExists(for: movie.url) {
                // Use existing proxy
                proxyURL = ProxyManager.getProxyURL(for: movie.url)
                print("Using existing proxy")
                
                await MainActor.run {
                    targetProgress = 1.0
                }
                // Wait for smooth animation to catch up
                try? await Task.sleep(nanoseconds: 300_000_000)
            } else {
                // Update message when we start proxy generation
                await MainActor.run {
                    processingMessage = "Optimizing video for playback..."
                    // Set target to at least 30% when starting proxy
                    if targetProgress < 0.30 {
                        targetProgress = 0.30
                    }
                }
                
                do {
                    let proxy = try await ProxyManager.generateProxy(
                        from: movie.url,
                        progress: { progress in
                            Task { @MainActor in
                                // Map proxy generation progress to 30-100%
                                self.targetProgress = 0.30 + (progress * 0.70)
                            }
                        }
                    )
                    proxyURL = proxy
                    print("Proxy generation complete")
                } catch {
                    print("Error generating proxy: \(error)")
                    // Continue without proxy - will use original
                    proxyURL = nil
                }
            }
            
            // Ensure we reach 100% smoothly
            await MainActor.run {
                targetProgress = 1.0
            }
            // Brief wait for animation to finish
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            smoothProgressTask.cancel()
            isProcessing = false
            processingProgress = 0.0
            targetProgress = 0.0
            processingMessage = ""
        } catch {
            importAnimationTask.cancel()
            smoothProgressTask.cancel()
            print("Error loading video: \(error)")
            isProcessing = false
        }
    }
}

// Helper struct to transfer video files from PhotosPicker
struct VideoFile: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "video-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

#Preview {
    EntryView()
}
