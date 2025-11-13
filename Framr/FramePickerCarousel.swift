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
    @Binding var isCarouselScrolling: Bool
    @Binding var isScrubbing: Bool
    
    @State private var scrollPosition: Int?
    @State private var isUserScrolling = false
    @State private var lastSeekFrame: Int?
    @State private var seekDebounceTask: Task<Void, Never>?
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var lastUserInteractionTime: Date?
    
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
                scrollPhase = newPhase
                isUserScrolling = newPhase == .interacting || newPhase == .decelerating || newPhase == .animating
                isCarouselScrolling = isUserScrolling
                
                // Track when user last interacted
                if newPhase == .interacting {
                    lastUserInteractionTime = Date()
                }
            }
            .onChange(of: scrollPosition) { oldValue, newValue in
                // Debounced seeking as user scrolls
                if let frameIndex = newValue, isUserScrolling {
                    // Only seek if we've moved to a different frame
                    if lastSeekFrame != frameIndex {
                        // Cancel previous debounce task
                        seekDebounceTask?.cancel()
                        
                        // Create new debounced seek task
                        seekDebounceTask = Task {
                            // 50ms debounce - imperceptible but prevents race conditions
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            
                            // Check if task wasn't cancelled
                            guard !Task.isCancelled else { return }
                            
                            // Perform the seek
                            await MainActor.run {
                                playerManager.seekToFrame(frameIndex)
                                lastSeekFrame = frameIndex
                            }
                        }
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
                
                // Don't update if already at correct position
                guard scrollPosition != newValue else { return }
                
                // Don't update while user is scrolling
                guard !isUserScrolling else { return }
                
                // Don't update while ThumbnailScrubber is being used
                guard !isScrubbing else { return }
                
                // Don't update if scroll phase is not idle (prevents conflicts during animations)
                guard scrollPhase == .idle else { return }
                
                // Debounce: wait 200ms after last user interaction before accepting external updates
                // This prevents snap-back when the user just finished scrolling
                if let lastInteraction = lastUserInteractionTime {
                    let timeSinceInteraction = Date().timeIntervalSince(lastInteraction)
                    guard timeSinceInteraction > 0.2 else { return }
                }
                
                // Only update if frame difference is significant (prevents jitter from minor variations)
                let frameDifference = abs(newValue - (scrollPosition ?? 0))
                guard frameDifference >= 1 else { return }
                
                // Animate the scroll for smooth centering
                withAnimation(.easeInOut(duration: 0.3)) {
                    scrollPosition = newValue
                    lastSeekFrame = newValue
                }
            }
            .onDisappear {
                // Cancel pending seek task to prevent memory leaks
                seekDebounceTask?.cancel()
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
            FramePickerCarousel(playerManager: VideoPlayerManager(url: url), isCarouselScrolling: .constant(false), isScrubbing: .constant(false))
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

