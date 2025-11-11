//
//  FrameGrabView.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import SwiftUI
import AVKit
import PhotosUI

struct FrameGrabView: View {
    let videoURL: URL
    @Binding var selectedVideo: PhotosPickerItem?
    @State private var playerManager: VideoPlayerManager
    
    init(videoURL: URL, selectedVideo: Binding<PhotosPickerItem?>) {
        self.videoURL = videoURL
        self._selectedVideo = selectedVideo
        self._playerManager = State(initialValue: VideoPlayerManager(url: videoURL))
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Navigation Bar
                topNavigationBar
                
                Spacer()
                
                // Video Player Area
                videoPlayerSection
                
                Spacer()
                
                // Thumbnail Scrubber
                thumbnailScrubber
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                
                // Bottom Controls
                bottomControls
                    .padding(.bottom, 40)
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
                    .glassEffect(.regular.interactive().tint(.white.opacity(0.1)))
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
                    .glassEffect(.regular.interactive().tint(.white.opacity(0.1)))
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    // MARK: - Video Player Section
    private var videoPlayerSection: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Video Player
                VideoPlayer(player: playerManager.player)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .disabled(true) // Disable default controls
                
                // Timecode Overlay
                Text(playerManager.formattedTime(playerManager.currentTime))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.black.opacity(0.3)))
                    .padding(.bottom, 20)
            }
        }
        .frame(maxHeight: 600)
    }
    
    // MARK: - Thumbnail Scrubber
    private var thumbnailScrubber: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Thumbnail strip - all thumbnails visible at once
                    HStack(spacing: 1) {
                        ForEach(0..<playerManager.thumbnails.count, id: \.self) { index in
                            Image(uiImage: playerManager.thumbnails[index])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width / CGFloat(max(playerManager.thumbnails.count, 1)), height: 40)
                                .clipped()
                        }
                    }
                    .opacity(0.6)
                    .cornerRadius(8)
                    
                    // Seek indicator - draggable
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 4)
                        .glassEffect(.regular.tint(.white))
                        .offset(x: geometry.size.width * playerManager.getCurrentProgress() - 2)
                        .shadow(color: .white.opacity(0.5), radius: 4)
                }
                .frame(height: 40)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percentage = max(0, min(1, value.location.x / geometry.size.width))
                            playerManager.seekToPercentage(percentage)
                        }
                )
            }
            .frame(height: 40)
            .cornerRadius(8)
            .glassEffect(.regular.tint(.white.opacity(0.05)))
        }
    }
    
    // MARK: - Bottom Controls
    private var bottomControls: some View {
        HStack(spacing: 40) {
            // Previous Frame Button
            Button(action: {
                playerManager.previousFrame()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 70, height: 70)
                    .glassEffect(.regular.interactive().tint(.white.opacity(0.1)))
            }
            
            // Play/Pause Button
            Button(action: {
                playerManager.togglePlayPause()
            }) {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .glassEffect(.regular.interactive().tint(.blue.opacity(0.3)))
            }
            
            // Next Frame Button
            Button(action: {
                playerManager.nextFrame()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 70, height: 70)
                    .glassEffect(.regular.interactive().tint(.white.opacity(0.1)))
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
            description: Text("Add 'SampleVideo.mp4' to the project bundle to preview")
        )
    }
    #endif
}
