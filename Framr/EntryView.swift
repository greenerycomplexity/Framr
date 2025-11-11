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
        ZStack {
            if (selectedVideo != nil) {
                EmptyView()
            }
            else {
                NoVideoView(selectedVideo: $selectedVideo)
            }
        }
        .preferredColorScheme(.dark)
    }

}

#Preview {
    EntryView()
}
