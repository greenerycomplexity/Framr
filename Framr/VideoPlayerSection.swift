//
//  VideoPlayerSection.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import AVKit
import SwiftUI

struct VideoPlayerSection: View {
    @Bindable var playerManager: VideoPlayerManager
    @Binding var isZooming: Bool
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Video Player
                VideoPlayer(player: playerManager.player)
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .scaleEffect(scale)
                    .offset(offset)
                    .disabled(true)  // Disable default controls
                
                // Transparent gesture overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                                // Set zooming state when scale exceeds threshold
                                if scale > 1.01 {
                                    isZooming = true
                                }
                            }
                            .onEnded { _ in
                                // Animate back to original state
                                withAnimation(.spring(response: 0.3)) {
                                    scale = 1.0
                                    offset = .zero
                                }
                                lastScale = 1.0
                                lastOffset = .zero
                                isZooming = false
                            }
                            .simultaneously(with: DragGesture()
                                .onChanged { value in
                                    // Only allow panning when zoomed in
                                    if scale > 1.01 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                            )
                    )

                // Timecode Overlay
                if !isZooming {
                    Text(playerManager.formattedTime(playerManager.currentTime))
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassEffect(.clear.tint(.black.opacity(0.3)))
                        .padding(.bottom, 10)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxHeight: 600)
    }
}

#Preview {
    #if DEBUG
        if let url = PreviewHelpers.sampleVideoURL {
            VideoPlayerSection(
                playerManager: VideoPlayerManager(url: url),
                isZooming: .constant(false)
            )
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

