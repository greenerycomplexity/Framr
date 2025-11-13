//
//  FramePickerCarousel.swift
//  Framr
//
//  Created by Son Cao on 11/12/25.
//

import SwiftUI
import AVFoundation
import UIKit

struct FramePickerCarousel: View {
    @Bindable var playerManager: VideoPlayerManager
    @Binding var isCarouselScrolling: Bool
    @Binding var isScrubbing: Bool
    
    @State private var isUserScrolling = false
    @State private var isDragging = false
    @State private var lastSeekFrame: Int?
    @State private var seekDebounceTask: Task<Void, Never>?
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var lastUserInteractionTime: Date?
    @State private var lastCarouselSeekTime: Date?
    @State private var centerFrameIndex: Int = 0
    
    private let frameHeight: CGFloat = 60
    private let frameWidth:CGFloat = 40
    private let frameSpacing: CGFloat = 8
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .soft)
    
    var body: some View {
        GeometryReader { geometry in
            let viewportWidth = geometry.size.width
            
            ScrollViewReader { proxy in
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
                                !isDragging && centerFrameIndex == frameIndex ? 1.15 : 0.9
                            )
                            .padding(.horizontal, !isDragging && centerFrameIndex == frameIndex ? 4 : 0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: centerFrameIndex)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
                            .id(frameIndex)
                            .background(
                                GeometryReader { itemGeometry in
                                    Color.clear
                                        .preference(
                                            key: FrameOffsetPreferenceKey.self,
                                            value: [frameIndex: itemGeometry.frame(in: .named("scrollView")).midX]
                                        )
                                }
                            )
                        }
                    }
                    .padding(.horizontal, viewportWidth / 2 - frameWidth / 2)
                }
                .coordinateSpace(name: "scrollView")
                .scrollIndicators(.hidden)
                .onPreferenceChange(FrameOffsetPreferenceKey.self) { frameOffsets in
                    // Calculate which frame is closest to the center of viewport
                    let center = viewportWidth / 2
                    var closestFrame = 0
                    var minDistance = CGFloat.infinity
                    
                    for (frameIndex, frameMidX) in frameOffsets {
                        let distance = abs(frameMidX - center)
                        if distance < minDistance {
                            minDistance = distance
                            closestFrame = frameIndex
                        }
                    }
                    
                    // Update center frame index
                    if centerFrameIndex != closestFrame {
                        centerFrameIndex = closestFrame
                        
                        // Trigger haptic feedback when center frame changes
                        // Only during user scrolling and not while video is playing
                        if isUserScrolling && !playerManager.isPlaying {
                            hapticGenerator.impactOccurred()
                        }
                        
                        // Seek to this frame if user is scrolling
                        if isUserScrolling && lastSeekFrame != closestFrame && !playerManager.isPlaying {
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
                                    playerManager.seekToFrame(closestFrame)
                                    lastSeekFrame = closestFrame
                                    lastCarouselSeekTime = Date()
                                }
                            }
                        }
                    }
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    scrollPhase = newPhase
                    isDragging = newPhase == .interacting
                    // Only .interacting and .decelerating are user-initiated
                    // Exclude .animating to prevent programmatic scrolls from triggering seeks
                    isUserScrolling = newPhase == .interacting || newPhase == .decelerating
                    isCarouselScrolling = isUserScrolling
                    
                    // Track when user last interacted
                    if newPhase == .interacting {
                        lastUserInteractionTime = Date()
                    }
                }
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.15),
                            .init(color: .black, location: 0.85),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .onAppear {
                    // Prepare haptic generator for low latency
                    hapticGenerator.prepare()
                    
                    // Set initial scroll position to current frame (centered)
                    if centerFrameIndex == 0 {
                        centerFrameIndex = playerManager.currentFrameIndex
                        lastSeekFrame = playerManager.currentFrameIndex
                        proxy.scrollTo(playerManager.currentFrameIndex, anchor: .center)
                    }
                }
                .onChange(of: playerManager.currentFrameIndex) { oldValue, newValue in
                    // Only update scroll position when NOT actively scrolling
                    // (e.g., from the main scrubber or play controls)
                    
                    // Don't update if already at correct position
                    guard centerFrameIndex != newValue else { return }
                    
                    // Don't update while video is playing
                    guard !playerManager.isPlaying else { return }
                    
                    // Don't update while user is scrolling
                    guard !isUserScrolling else { return }
                    
                    // Don't update while ThumbnailScrubber is being used
                    guard !isScrubbing else { return }
                    
                    // Don't update if scroll phase is not idle (prevents conflicts during animations)
                    guard scrollPhase == .idle else { return }
                    
                    // Ignore updates from carousel-initiated seeks (wait 500ms after carousel seek)
                    // This prevents snap-back from time observer reporting stale/rounded frame indices
                    if let lastCarouselSeek = lastCarouselSeekTime {
                        let timeSinceCarouselSeek = Date().timeIntervalSince(lastCarouselSeek)
                        guard timeSinceCarouselSeek > 0.5 else { return }
                    }
                    
                    // Debounce: wait 500ms after last user interaction before accepting external updates
                    // This prevents snap-back when the user just finished scrolling
                    if let lastInteraction = lastUserInteractionTime {
                        let timeSinceInteraction = Date().timeIntervalSince(lastInteraction)
                        guard timeSinceInteraction > 0.5 else { return }
                    }
                    
                    // Only update if frame difference is significant (prevents jitter from minor variations)
                    // Using threshold of 3 to ignore timing jitter from the time observer
                    let frameDifference = abs(newValue - centerFrameIndex)
                    guard frameDifference >= 3 else { return }
                    
                    // Animate the scroll to center the frame
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                    centerFrameIndex = newValue
                    lastSeekFrame = newValue
                }
                .onChange(of: isScrubbing) { oldValue, newValue in
                    // When scrubbing ends, immediately sync carousel to current frame
                    if oldValue == true && newValue == false {
                        let currentFrame = playerManager.currentFrameIndex
                        
                        // Only update if we're not already at the right position
                        if centerFrameIndex != currentFrame {
                            // Use a small delay to let the scrubber's final seek settle
                            Task {
                                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                                await MainActor.run {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(currentFrame, anchor: .center)
                                    }
                                    centerFrameIndex = currentFrame
                                    lastSeekFrame = currentFrame
                                }
                            }
                        }
                    }
                }
                .onDisappear {
                    // Cancel pending seek task to prevent memory leaks
                    seekDebounceTask?.cancel()
                }
            }
        }
        .frame(height: frameHeight + 20)
    }
}

// MARK: - Preference Key for Frame Offsets

struct FrameOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
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

