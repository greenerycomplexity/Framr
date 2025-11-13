//
//  NoVideoView.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import PhotosUI
import SwiftUI

struct NoVideoView: View {
    @Binding var selectedVideo: PhotosPickerItem?
    @State private var galleryTapped = false

    var body: some View {
        VStack(alignment: .leading) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
                .padding(.bottom, 5)

            Text("Welcome to Framr")
                .font(.title.bold())

            Text("Select a video to extract still images from")
                .font(.headline)
                .foregroundStyle(.secondary)

            PhotosPicker(selection: $selectedVideo, matching: .videos) {
                HStack {
                    Image(systemName: "photo.stack")
                    Text("Open Gallery...")
                        .bold()
                }
                .padding(.vertical, 20)
                .frame(width: 350)
                .foregroundStyle(.white)
                .glassEffect(.regular.interactive().tint(.blue))
                .padding(.top, 10)
                
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    galleryTapped.toggle()
                }
            )
            .sensoryFeedback(.impact, trigger: galleryTapped)
        }
    }
}

#Preview {
    NoVideoView(selectedVideo: .constant(nil))
}
