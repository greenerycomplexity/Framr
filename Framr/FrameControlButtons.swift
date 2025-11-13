//
//  FrameControlButtons.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import SwiftUI

struct FrameControlButtons: View {
    @Bindable var playerManager: VideoPlayerManager
    let onSaveFrame: () -> Void

    @State private var playTapped = false
    @State private var saveTapped = false

    var body: some View {
        VStack {
            HStack(alignment: .bottom, spacing: 40) {

                VStack(spacing: 16) {
                    // Play/Pause Button
                    Button(action: {
                        playTapped.toggle()
                        playerManager.togglePlayPause()
                    }) {
                        Image(
                            systemName: playerManager.isPlaying
                                ? "pause.fill" : "play.fill"
                        )
                        //                        .font(.system(size: 22, weight: .semibold))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        //                        .frame(width: 80, height: 80)
                        .frame(width: 100, height: 100)
                        .glassEffect(.clear.interactive())
                        .sensoryFeedback(.selection, trigger: playTapped)

                    }

                    Text(
                        playerManager.isPlaying
                            ? "Pause" : "Play"
                    )
                    .font(.headline)
                }

                VStack(spacing: 16) {

                    // Save frame button
                    Button(action: {
                        saveTapped.toggle()
                        onSaveFrame()
                    }) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 100, height: 100)
//                            .offset(y: -5)
                            .glassEffect(
                                .clear.interactive().tint(.orange)
                            )
                            .sensoryFeedback(
                                .impact(weight: .heavy),
                                trigger: saveTapped
                            )
                    }

                    Text("Save Frame")
                        .font(.headline)

                }
            }

        }
    }
}

#Preview {
    #if DEBUG
        if let url = PreviewHelpers.sampleVideoURL {
            FrameControlButtons(
                playerManager: VideoPlayerManager(url: url),
                onSaveFrame: {
                    print("Save frame tapped")
                }
            )
            .frame(width: 400, height: 400)
            .background(Color.black)
            .preferredColorScheme(.dark)
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
