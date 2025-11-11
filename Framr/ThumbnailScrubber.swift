//
//  ThumbnailScrubber.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import SwiftUI

struct ThumbnailScrubber: View {
    @Bindable var playerManager: VideoPlayerManager
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Thumbnail strip - all thumbnails visible at once
                    HStack(spacing: 1) {
                        ForEach(0..<playerManager.thumbnails.count, id: \.self)
                        { index in
                            Image(uiImage: playerManager.thumbnails[index])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(
                                    width: geometry.size.width
                                        / CGFloat(
                                            max(
                                                playerManager.thumbnails.count,
                                                1
                                            )
                                        ),
                                    height: 40
                                )
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
                        .offset(
                            x: geometry.size.width
                                * playerManager.getCurrentProgress() - 2
                        )
                        .shadow(color: .white.opacity(0.5), radius: 4)
                }
                .frame(height: 40)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percentage = max(
                                0,
                                min(1, value.location.x / geometry.size.width)
                            )
                            playerManager.seekToPercentage(percentage)
                        }
                )
            }
            .frame(height: 40)
            .cornerRadius(8)
            .glassEffect(.regular.tint(.white.opacity(0.05)))
        }
    }
}

#Preview {
    #if DEBUG
        if let url = PreviewHelpers.sampleVideoURL {
            ThumbnailScrubber(playerManager: VideoPlayerManager(url: url))
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

