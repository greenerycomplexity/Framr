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
        processingMessage = "Loading video..."
        
        do {
            // Step 1: Load video file (0-10% progress)
            guard let movie = try await item.loadTransferable(type: VideoFile.self) else {
                isProcessing = false
                return
            }
            videoURL = movie.url
            
            await MainActor.run {
                processingProgress = 0.1
            }
            
            // Step 2: Always generate 1080p proxy for all videos
            // Check if proxy already exists
            if ProxyManager.proxyExists(for: movie.url) {
                // Use existing proxy
                proxyURL = ProxyManager.getProxyURL(for: movie.url)
                print("Using existing proxy")
                
                await MainActor.run {
                    processingProgress = 1.0
                }
            } else {
                // Generate new proxy (10-100% progress)
                processingMessage = "Optimizing video for playback..."
                
                do {
                    let proxy = try await ProxyManager.generateProxy(
                        from: movie.url,
                        progress: { progress in
                            Task { @MainActor in
                                // Map proxy generation progress to 10-100%
                                self.processingProgress = 0.1 + (progress * 0.9)
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
            
            isProcessing = false
            processingProgress = 0.0
            processingMessage = ""
        } catch {
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
