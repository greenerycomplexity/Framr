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
            HStack(spacing: 40) {

                // Play/Pause Button
                Button(action: {
                    playTapped.toggle()
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
                    .sensoryFeedback(.selection, trigger: playTapped)
                    
                }
                
                
                // Save frame button
                Button(action: {
                    saveTapped.toggle()
                    onSaveFrame()
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 100, height: 100)
                        .offset(y:-5)
                        .glassEffect(.regular.interactive().tint(.blue.opacity(0.3))
                        )
                        .sensoryFeedback(.impact(weight: .heavy), trigger: saveTapped)
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

