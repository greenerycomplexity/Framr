//
//  FramePickerCarousel.swift
//  Framr
//
//  Created by Son Cao on 11/12/25.
//

import SwiftUI
import AVFoundation

struct FramePickerCarousel: View {
    @Bindable var playerManager: VideoPlayerManager
    
    @State private var scrollPosition: Int?
    @State private var isUserScrolling = false
    @State private var lastSeekFrame: Int?
    
    private let frameHeight: CGFloat = 60
    private let frameWidth:CGFloat = 40
    private let frameSpacing: CGFloat = 8
    
    var body: some View {
        GeometryReader { geometry in
//            let frameWidth = (geometry.size.width - (frameSpacing * 5)) / 10
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: frameSpacing) {
                    ForEach(0..<playerManager.totalFrameCount, id: \.self) { frameIndex in
                        FrameThumbnailView(
                            playerManager: playerManager,
                            frameIndex: frameIndex,
                            width: frameWidth,
                            height: frameHeight
                        )
                        .scaleEffect(
                            scrollPosition == frameIndex ? 1.15 : 1.0
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: scrollPosition)
                        .id(frameIndex)
                    }
                }
                .padding(.horizontal, geometry.size.width / 2 - frameWidth / 2)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPosition, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { oldPhase, newPhase in
                isUserScrolling = newPhase == .interacting || newPhase == .decelerating
            }
            .onChange(of: scrollPosition) { oldValue, newValue in
                // Seek in real-time as user scrolls
                if let frameIndex = newValue, isUserScrolling {
                    // Only seek if we've moved to a different frame
                    if lastSeekFrame != frameIndex {
                        playerManager.seekToFrame(frameIndex)
                        lastSeekFrame = frameIndex
                    }
                }
            }
//            .mask(
//                LinearGradient(
//                    gradient: Gradient(stops: [
//                        .init(color: .clear, location: 0),
//                        .init(color: .black, location: 0.1),
//                        .init(color: .black, location: 0.9),
//                        .init(color: .clear, location: 1.0)
//                    ]),
//                    startPoint: .leading,
//                    endPoint: .trailing
//                )
//            )
            .onAppear {
                // Set initial scroll position to current frame
                if scrollPosition == nil {
                    scrollPosition = playerManager.currentFrameIndex
                    lastSeekFrame = playerManager.currentFrameIndex
                }
            }
            .onChange(of: playerManager.currentFrameIndex) { oldValue, newValue in
                // Only update scroll position when NOT actively scrolling
                // (e.g., from the main scrubber or play controls)
                if !isUserScrolling && scrollPosition != newValue {
                    scrollPosition = newValue
                    lastSeekFrame = newValue
                }
            }
        }
        .frame(height: frameHeight + 20)
    }
}

// MARK: - Frame Thumbnail View

struct FrameThumbnailView: View {
    @Bindable var playerManager: VideoPlayerManager
    let frameIndex: Int
    let width: CGFloat
    let height: CGFloat
    
    @State private var thumbnail: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: width, height: height)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard thumbnail == nil, !isLoading else { return }
        
        isLoading = true
        Task {
            if let cachedThumbnail = await playerManager.getFrameThumbnail(at: frameIndex) {
                await MainActor.run {
                    thumbnail = cachedThumbnail
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    #if DEBUG
        if let url = PreviewHelpers.sampleVideoURL {
            FramePickerCarousel(playerManager: VideoPlayerManager(url: url))
                .padding()
                .background(Color.black)
        } else {
            ContentUnavailableView(
                "No Preview Video",
                systemImage: "video.slash",
                description: Text(
                    "Add 'SampleVideo.MOV' to the project bundle to preview"
                )
            )
        }
    #endif
}

