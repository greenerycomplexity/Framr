//
//  PreviewHelpers.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

#if DEBUG
import Foundation

struct PreviewHelpers {
    /// Returns a URL to the bundled sample video for preview purposes
    static var sampleVideoURL: URL? {
        Bundle.main.url(forResource: "SampleVideo", withExtension: "MOV")
    }
    
    /// Returns a guaranteed URL for preview (creates a temporary file if bundle resource not found)
    static var previewVideoURL: URL {
        if let bundleURL = sampleVideoURL {
            return bundleURL
        }
        
        // Fallback: return a path that won't crash the preview
        // (SwiftUI previews might not have access to bundle resources)
        return URL(fileURLWithPath: "/dev/null")
    }
}
#endif

