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
    
    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Text(isSuccess ? "✅" : "❌")
                    .font(.headline)

                Text(message)
//                    .font(.system(size: 14, weight: .semibold))
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassEffect(.regular)
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .padding(.bottom, 315)
        }
    }
}

#Preview("Success Banner") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        StatusBanner(
            message: "Frame saved to Photos!",
            isSuccess: true,
        )
    }
}

#Preview("Error Banner") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        StatusBanner(
            message: "Failed to save frame",
            isSuccess: false,
        )
    }
}

