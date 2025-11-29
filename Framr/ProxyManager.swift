//
//  ProxyManager.swift
//  Framr
//
//  Created by Son Cao on 11/19/25.
//

import Foundation
import AVFoundation
import CryptoKit

enum ProxyError: Error {
    case fileNotFound
    case exportFailed(String)
    case invalidAsset
}

class ProxyManager {
    // 50MB threshold
    private static let proxySizeThreshold: Int64 = 52_428_800
    
    // Get the Cache directory for storing proxy files
    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoProxies", isDirectory: true)
    }
    
    /// Check if a video file needs a proxy based on file size
    static func needsProxy(for url: URL) -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return fileSize > proxySizeThreshold
            }
            return false
        } catch {
            print("Error checking file size: \(error)")
            return false
        }
    }
    
    /// Generate a unique proxy URL based on the original video URL
    static func getProxyURL(for originalURL: URL) -> URL {
        // Create a hash of the original URL path for uniqueness
        let originalPath = originalURL.path
        let hash = SHA256.hash(data: Data(originalPath.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16)
        
        // Get the original filename without extension
        let originalFileName = originalURL.deletingPathExtension().lastPathComponent
        
        // Create proxy filename: proxy-{originalFileName}-{hash}.mp4
        let proxyFileName = "proxy-\(originalFileName)-\(hashString).mp4"
        
        return cacheDirectory.appendingPathComponent(proxyFileName)
    }
    
    /// Check if a proxy already exists for the given original video
    static func proxyExists(for originalURL: URL) -> Bool {
        let proxyURL = getProxyURL(for: originalURL)
        return FileManager.default.fileExists(atPath: proxyURL.path)
    }
    
    /// Generate a 1080p H.264 proxy video with progress tracking
    static func generateProxy(
        from originalURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        // Check if proxy already exists
        let proxyURL = getProxyURL(for: originalURL)
        
        if proxyExists(for: originalURL) {
            print("Proxy already exists at: \(proxyURL.path)")
            progress(1.0)
            return proxyURL
        }
        
        // Ensure cache directory exists
        try ensureCacheDirectoryExists()
        
        // Create asset from original video
        let asset = AVURLAsset(url: originalURL)
        
        // Verify asset is valid
        guard try await asset.load(.isExportable) else {
            throw ProxyError.invalidAsset
        }
        
        // Create export session with 1080p preset
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1920x1080
        ) else {
            throw ProxyError.exportFailed("Could not create export session")
        }
        
        // Configure export session
        exportSession.outputURL = proxyURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Use withCheckedThrowingContinuation to properly track progress during export
        return try await withCheckedThrowingContinuation { continuation in
            // Start progress monitoring BEFORE export begins
            let progressTask = Task {
                while !Task.isCancelled {
                    let currentProgress = Double(exportSession.progress)
                    await MainActor.run {
                        progress(currentProgress)
                    }
                    
                    // Check if export is no longer in progress
                    if exportSession.status != .exporting && exportSession.status != .waiting {
                        break
                    }
                    
                    try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds for smoother updates
                }
            }
            
            // Start export asynchronously with completion handler
            exportSession.exportAsynchronously {
                progressTask.cancel()
                
                switch exportSession.status {
                case .completed:
                    progress(1.0)
                    print("Proxy generated successfully at: \(proxyURL.path)")
                    continuation.resume(returning: proxyURL)
                    
                case .failed:
                    let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
                    continuation.resume(throwing: ProxyError.exportFailed(errorMessage))
                    
                case .cancelled:
                    continuation.resume(throwing: ProxyError.exportFailed("Export was cancelled"))
                    
                default:
                    continuation.resume(throwing: ProxyError.exportFailed("Export ended with unexpected status: \(exportSession.status.rawValue)"))
                }
            }
        }
    }
    
    /// Ensure the cache directory exists, create it if needed
    private static func ensureCacheDirectoryExists() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            print("Created proxy cache directory at: \(cacheDirectory.path)")
        }
    }
    
    /// Clean up old proxy files (optional utility method)
    static func cleanupOldProxies(olderThan days: Int = 30) throws {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: cacheDirectory.path) else {
            return
        }
        
        let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))
        let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey])
        
        for file in files {
            if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
               creationDate < cutoffDate {
                try fileManager.removeItem(at: file)
                print("Removed old proxy: \(file.lastPathComponent)")
            }
        }
    }
    
    /// Delete a specific proxy file
    static func deleteProxy(for originalURL: URL) throws {
        let proxyURL = getProxyURL(for: originalURL)
        if FileManager.default.fileExists(atPath: proxyURL.path) {
            try FileManager.default.removeItem(at: proxyURL)
            print("Deleted proxy at: \(proxyURL.path)")
        }
    }
}

