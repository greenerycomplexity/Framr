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
                    .disabled(true)  // Disable default controls

                // Timecode Overlay
                Text(playerManager.formattedTime(playerManager.currentTime))
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.black.opacity(0.3)))
                    .padding(.bottom, 20)
            }
        }
        .frame(maxHeight: 600)
    }
}

#Preview {
    #if DEBUG
        if let url = PreviewHelpers.sampleVideoURL {
            VideoPlayerSection(playerManager: VideoPlayerManager(url: url))
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

