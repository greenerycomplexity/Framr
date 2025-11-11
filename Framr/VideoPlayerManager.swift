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
        let interval = CMTime(seconds: 0.01, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time
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
        } catch {
            print("Error loading duration: \(error)")
        }
    }
    
    func generateThumbnails() async {
        guard let asset = asset else { return }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 200, height: 112) // 16:9 aspect ratio thumbnail
        
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            // Generate 20 thumbnails evenly distributed
            let thumbnailCount = 20
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
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
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
    
    deinit {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

