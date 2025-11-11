//
//  StatusBanner.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import SwiftUI

struct StatusBanner: View {
    let message: String
    let isSuccess: Bool
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Text(isSuccess ? "✅" : "❌")
                    .font(.system(size: 24))

                Text(message)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .glassEffect(.regular)
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .padding(.bottom, 120)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: isVisible)
        }
    }
}

#Preview("Success Banner") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        StatusBanner(
            message: "Frame saved to Photos!",
            isSuccess: true,
            isVisible: .constant(true)
        )
    }
}

#Preview("Error Banner") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        StatusBanner(
            message: "Failed to save frame",
            isSuccess: false,
            isVisible: .constant(true)
        )
    }
}

