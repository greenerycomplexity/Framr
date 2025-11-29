//
//  SharingActionView.swift
//  Framr
//
//  Created by Son Cao on 29/11/25.
//

import SwiftUI

struct SharingActionView: View {
    @Binding var selectedAction: SharingAction
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                ForEach(SharingAction.allCases, id: \.self) { action in
                    Button {
                        selectedAction = action
                    } label: {
                        HStack {
                            Image(systemName: action.icon)
                                .frame(width: 24)
                            
                            Text(action.displayName)
                            
                            Spacer()
                            
                            if selectedAction == action {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            } footer: {
                Text("Save to Photos will save frames directly to your photo library. Open Share Sheet allows you to share or save to other apps.")
            }
        }
        .navigationTitle("Sharing Action")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SharingActionView(selectedAction: .constant(.saveToPhotos))
    }
    .preferredColorScheme(.dark)
}

