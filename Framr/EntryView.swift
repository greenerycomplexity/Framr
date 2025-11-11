//
//  EntryView.swift
//  Framr
//
//  Created by Son Cao on 10/11/25.
//

import SwiftUI
import PhotosUI

struct EntryView: View {
    @State private var selectedVideo: PhotosPickerItem? = nil
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Image (systemName: "camera.viewfinder")
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
//                        Image(systemName: "photo.on.rectangle.angled.fill")\
                        Image(systemName: "photo.stack")
                        Text("Open Gallery...")
                            .bold()
                    }
                    .padding()
                    .padding(.horizontal, 50)
                    .foregroundStyle(.white)
                    .glassEffect(.regular.interactive().tint(.blue))
                    .padding(.top, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

}

#Preview {
    EntryView()
}
