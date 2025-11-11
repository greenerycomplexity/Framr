//
//  FrameControlButtons.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import SwiftUI

struct FrameControlButtons: View {
    @Bindable var playerManager: VideoPlayerManager
    let isSaving: Bool
    let onSaveFrame: () -> Void
    
    var body: some View {
        VStack {
            HStack(spacing: 40) {
                // Previous Frame Button
                Button(action: {
                    playerManager.previousFrame()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 70)
                        .glassEffect(
                            .regular.interactive().tint(.white.opacity(0.1))
                        )
                }

                // Save frame button
                Button(action: {
                    onSaveFrame()
                }) {
                    ZStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(
                                    CircularProgressViewStyle(tint: .white)
                                )
                                .scaleEffect(1.5)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 32, weight: .semibold))
                                .offset(y: -5)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 100, height: 100)
                    .glassEffect(
                        .regular.interactive().tint(.blue.opacity(0.3))
                    )
                }
                .disabled(isSaving)

                // Next Frame Button
                Button(action: {
                    playerManager.nextFrame()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 70, height: 70)
                        .glassEffect(
                            .regular.interactive().tint(.white.opacity(0.1))
                        )
                }
            }
            // Play/Pause Button
            Button(action: {
                playerManager.togglePlayPause()
            }) {
                Image(
                    systemName: playerManager.isPlaying
                        ? "pause.fill" : "play.fill"
                )
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .glassEffect(.regular.interactive().tint(.white.opacity(0.3)))
            }
        }
    }
}

#Preview {
    #if DEBUG
        if let url = PreviewHelpers.sampleVideoURL {
            FrameControlButtons(
                playerManager: VideoPlayerManager(url: url),
                isSaving: false,
                onSaveFrame: {
                    print("Save frame tapped")
                }
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

