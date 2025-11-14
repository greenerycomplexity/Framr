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
    
    // Thumbnail generation optimization
    private let thumbnailQueue = DispatchQueue(label: "com.framr.thumbnailQueue", qos: .userInitiated)
    private var activeThumbnailTasks: [Int: Task<UIImage?, Never>] = [:]
    private var thumbnailGenerator: AVAssetImageGenerator?
    
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
            setupThumbnailGenerator()
        } catch {
            print("Error loading duration: \(error)")
        }
    }
    
    private func setupThumbnailGenerator() {
        guard let asset = asset else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        // Optimized resolution for carousel display (40×60 points)
        // Using 3x scale max for retina, but actual display is small
        // This is 4x fewer pixels than before, resulting in 4x faster decode
        generator.maximumSize = CGSize(width: 80, height: 120)
        
        self.thumbnailGenerator = generator
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
        
        // Check if already generating this thumbnail
        if let existingTask = activeThumbnailTasks[frameIndex] {
            return await existingTask.value
        }
        
        // Create new task for this thumbnail
        let task = Task<UIImage?, Never> { @MainActor in
            guard let generator = self.thumbnailGenerator,
                  let frameRate = self.getFrameRate() else { return nil }
            
            let timeInSeconds = Double(frameIndex) / frameRate
            let time = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
            
            do {
                // Use serial queue to prevent concurrent generation
                // This ensures only one thumbnail is being decoded at a time
                let image: UIImage = try await withCheckedThrowingContinuation { continuation in
                    self.thumbnailQueue.async {
                        do {
                            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                            let uiImage = UIImage(cgImage: cgImage)
                            continuation.resume(returning: uiImage)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                
                // Cache the thumbnail and cleanup
                self.frameThumbnailCache[frameIndex] = image
                self.activeThumbnailTasks.removeValue(forKey: frameIndex)
                
                // LRU-style cache eviction - keep most recent frames
                if self.frameThumbnailCache.count > 200 {
                    // Sort keys and remove oldest 50 entries
                    let sortedKeys = self.frameThumbnailCache.keys.sorted()
                    let keysToRemove = sortedKeys.prefix(50)
                    keysToRemove.forEach { self.frameThumbnailCache.removeValue(forKey: $0) }
                }
                
                return image
            } catch {
                self.activeThumbnailTasks.removeValue(forKey: frameIndex)
                print("Error generating frame thumbnail at index \(frameIndex): \(error)")
                return nil
            }
        }
        
        // Store the task to prevent duplicate generation
        activeThumbnailTasks[frameIndex] = task
        return await task.value
    }
    
    /// Preload thumbnails around a specific frame index for faster perceived loading
    /// This runs in the background and caches thumbnails before they're needed
    func preloadThumbnailsAround(frameIndex: Int, range: Int = 20) {
        Task.detached(priority: .utility) {
            let start = max(0, frameIndex - range)
            let end = min(await self.totalFrameCount - 1, frameIndex + range)
            
            for index in start...end {
                // Skip if already cached
                let isCached = await MainActor.run {
                    self.frameThumbnailCache[index] != nil
                }
                if isCached {
                    continue
                }
                
                // Load the thumbnail (will be cached automatically)
                _ = await self.getFrameThumbnail(at: index)
            }
        }
    }
    
    deinit {
        // Pause the player before cleanup
        player.pause()
        
        // Cancel all active thumbnail tasks
        for (_, task) in activeThumbnailTasks {
            task.cancel()
        }
        activeThumbnailTasks.removeAll()
        
        // Remove time observer
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
}

