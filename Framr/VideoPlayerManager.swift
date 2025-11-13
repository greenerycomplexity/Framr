//
//  VideoPlayerManager.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import SwiftUI
import AVFoundation
import Combine

@Observable
class VideoPlayerManager {
    var player: AVPlayer
    var currentTime: CMTime = .zero
    var duration: CMTime = .zero
    var isPlaying: Bool = false
    var thumbnails: [UIImage] = []
    
    // Frame-by-frame navigation properties
    var totalFrameCount: Int = 0
    var currentFrameIndex: Int = 0
    private var frameThumbnailCache: [Int: UIImage] = [:]
    
    private var timeObserver: Any?
    private var asset: AVAsset?
    
    init(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        self.player = AVPlayer(playerItem: playerItem)
        self.asset = AVURLAsset(url: url)
        
        setupPlayer()
        Task {
            await loadDuration()
            await generateThumbnails()
        }
    }
    
    private func setupPlayer() {
        // Add periodic time observer
        // Using 1/30 second interval (30 fps) instead of 0.01s (100 fps)
        // This reduces unnecessary updates while still providing smooth UI
        let interval = CMTime(seconds: 1.0/30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time
            self?.updateCurrentFrameIndex()
        }
        
        // Observe player status
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.player.seek(to: .zero)
        }
    }
    
    private func loadDuration() async {
        guard let asset = asset else { return }
        do {
            let duration = try await asset.load(.duration)
            self.duration = duration
            await calculateTotalFrameCount()
        } catch {
            print("Error loading duration: \(error)")
        }
    }
    
    private func calculateTotalFrameCount() async {
        guard let frameRate = getFrameRate() else { return }
        let durationSeconds = CMTimeGetSeconds(duration)
        await MainActor.run {
            self.totalFrameCount = Int(durationSeconds * frameRate)
        }
    }
    
    private func updateCurrentFrameIndex() {
        guard let frameRate = getFrameRate(), totalFrameCount > 0 else { return }
        let currentSeconds = CMTimeGetSeconds(currentTime)
        let frameIndex = Int(currentSeconds * frameRate)
        self.currentFrameIndex = min(max(0, frameIndex), totalFrameCount - 1)
    }
    
    func generateThumbnails() async {
        guard let asset = asset else { return }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Generate at higher resolution for Retina displays
        let scale = UIScreen.main.scale
        imageGenerator.maximumSize = CGSize(
            width: 200 * scale,
            height: 112 * scale
        ) // 16:9 aspect ratio thumbnail
        
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            // Adaptive thumbnail count based on video duration
            let thumbnailCount: Int
            switch durationSeconds {
            case 0..<30:        // < 30s
                thumbnailCount = 10
            case 30..<120:      // 30s - 2min
                thumbnailCount = 20
            case 120..<600:     // 2min - 10min
                thumbnailCount = 40
            case 600..<1800:    // 10min - 30min
                thumbnailCount = 60
            case 1800..<3600:   // 30min - 1hr
                thumbnailCount = 80
            default:            // 1hr+
                thumbnailCount = 100
            }
            
            var times: [NSValue] = []
            for i in 0..<thumbnailCount {
                let time = CMTime(seconds: (durationSeconds / Double(thumbnailCount)) * Double(i), preferredTimescale: 600)
                times.append(NSValue(time: time))
            }
            
            var generatedThumbnails: [UIImage] = []
            
            for time in times {
                do {
                    let cgImage = try await imageGenerator.image(at: time.timeValue).image
                    let uiImage = UIImage(cgImage: cgImage)
                    generatedThumbnails.append(uiImage)
                } catch {
                    print("Error generating thumbnail: \(error)")
                }
            }
            
            await MainActor.run {
                self.thumbnails = generatedThumbnails
            }
        } catch {
            print("Error generating thumbnails: \(error)")
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func play() {
        player.play()
        isPlaying = true
    }
    
    func pause() {
        player.pause()
        isPlaying = false
    }
    
    func seek(to time: CMTime) {
        // Don't manually set currentTime - let the periodic observer update it
        // This prevents race conditions where we set the target time but the observer
        // immediately overwrites it with the actual (not-yet-seeked) player time
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func seekToPercentage(_ percentage: Double) {
        let time = CMTime(seconds: CMTimeGetSeconds(duration) * percentage, preferredTimescale: duration.timescale)
        seek(to: time)
    }
    
    func nextFrame() {
        guard let frameRate = getFrameRate() else { return }
        let frameDuration = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
        let newTime = CMTimeAdd(currentTime, frameDuration)
        
        if CMTimeCompare(newTime, duration) <= 0 {
            seek(to: newTime)
        }
    }
    
    func previousFrame() {
        guard let frameRate = getFrameRate() else { return }
        let frameDuration = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
        let newTime = CMTimeSubtract(currentTime, frameDuration)
        
        if CMTimeCompare(newTime, .zero) >= 0 {
            seek(to: newTime)
        }
    }
    
    private func getFrameRate() -> Double? {
        guard let track = player.currentItem?.asset.tracks(withMediaType: .video).first else {
            return 30.0 // Default fallback
        }
        return Double(track.nominalFrameRate)
    }
    
    func formattedTime(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        guard !seconds.isNaN && !seconds.isInfinite else {
            return "00:00:00:00"
        }
        
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * (getFrameRate() ?? 30.0))
        
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
    }
    
    func getCurrentProgress() -> Double {
        guard duration.seconds > 0 else { return 0 }
        return currentTime.seconds / duration.seconds
    }
    
    func captureCurrentFrame() async -> UIImage? {
        guard let asset = asset else { return nil }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        do {
            let cgImage = try await imageGenerator.image(at: currentTime).image
            return UIImage(cgImage: cgImage)
        } catch {
            print("Error capturing frame: \(error)")
            return nil
        }
    }
    
    // MARK: - Frame-by-frame Navigation
    
    func seekToFrame(_ frameIndex: Int) {
        guard let frameRate = getFrameRate(), frameIndex >= 0, frameIndex < totalFrameCount else { return }
        let timeInSeconds = Double(frameIndex) / frameRate
        let time = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
        seek(to: time)
    }
    
    func getFrameThumbnail(at frameIndex: Int) async -> UIImage? {
        // Check cache first
        if let cachedImage = frameThumbnailCache[frameIndex] {
            return cachedImage
        }
        
        // Generate thumbnail for this specific frame
        guard let asset = asset, let frameRate = getFrameRate() else { return nil }
        
        let timeInSeconds = Double(frameIndex) / frameRate
        let time = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        // Generate at higher resolution for Retina displays
        // Using 3x scale to ensure sharp thumbnails on all devices
        let scale = UIScreen.main.scale
        imageGenerator.maximumSize = CGSize(
            width: 120 * scale,
            height: 80 * scale
        )
        
        do {
            let cgImage = try await imageGenerator.image(at: time).image
            let uiImage = UIImage(cgImage: cgImage)
            
            // Cache the thumbnail
            await MainActor.run {
                frameThumbnailCache[frameIndex] = uiImage
                
                // Limit cache size to prevent memory issues
                if frameThumbnailCache.count > 100 {
                    // Remove random entries to keep cache size manageable
                    let keysToRemove = Array(frameThumbnailCache.keys.prefix(20))
                    for key in keysToRemove {
                        frameThumbnailCache.removeValue(forKey: key)
                    }
                }
            }
            
            return uiImage
        } catch {
            print("Error generating frame thumbnail: \(error)")
            return nil
        }
    }
    
    deinit {
        // Pause the player before cleanup
        player.pause()
        
        // Remove time observer
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
}

