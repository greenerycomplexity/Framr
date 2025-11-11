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
    @State private var isLoadingVideo = false
    
    var body: some View {
        ZStack {
            if let videoURL = videoURL {
                FrameGrabView(videoURL: videoURL, selectedVideo: $selectedVideo)
            }
            else if isLoadingVideo {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading video...")
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
            return
        }
        
        isLoadingVideo = true
        
        do {
            guard let movie = try await item.loadTransferable(type: VideoFile.self) else {
                isLoadingVideo = false
                return
            }
            videoURL = movie.url
        } catch {
            print("Error loading video: \(error)")
        }
        
        isLoadingVideo = false
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
