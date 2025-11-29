//
//  VideoPlayerManager.swift
//  Framr
//
//  Created by Son Cao on 11/11/25.
//

import SwiftUI
import AVFoundation
import Combine
import CoreLocation
import ImageIO

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
    
    // Dual-asset architecture
    private var originalAsset: AVAsset      // For high-quality frame extraction
    private var proxyAsset: AVAsset         // For playback (may be same as original)
    private var originalURL: URL            // Store original URL
    private var isUsingProxy: Bool = false  // Track if proxy is active
    
    // Thumbnail generation optimization
    private let thumbnailQueue = DispatchQueue(label: "com.framr.thumbnailQueue", qos: .userInitiated)
    private var activeThumbnailTasks: [Int: Task<UIImage?, Never>] = [:]
    private var thumbnailGenerator: AVAssetImageGenerator?
    
    // Cached video metadata (extracted once on load)
    private var cachedVideoMetadata: [String: Any]?
    private var cachedImageMetadata: [String: Any]?
    
    init(originalURL: URL, proxyURL: URL? = nil) {
        self.originalURL = originalURL
        let original = AVURLAsset(url: originalURL)
        self.originalAsset = original
        
        // Use proxy if provided, otherwise use original
        let proxy: AVAsset
        if let proxyURL = proxyURL {
            proxy = AVURLAsset(url: proxyURL)
            self.isUsingProxy = true
            print("VideoPlayerManager: Using proxy for playback")
        } else {
            proxy = original
            self.isUsingProxy = false
            print("VideoPlayerManager: Using original for playback")
        }
        self.proxyAsset = proxy
        
        // Player uses proxy asset for performance
        let playerItem = AVPlayerItem(asset: proxy)
        self.player = AVPlayer(playerItem: playerItem)
        
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
            guard let self = self else { return }
            self.isPlaying = false
            
            // Seek to the last frame instead of looping back to start
            if let frameRate = self.getFrameRate() {
                let frameDuration = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
                let lastFrameTime = CMTimeSubtract(self.duration, frameDuration)
                self.player.seek(to: lastFrameTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }
    
    private func loadDuration() async {
        do {
            let duration = try await proxyAsset.load(.duration)
            self.duration = duration
            await calculateTotalFrameCount()
            setupThumbnailGenerator()
            
            // Pre-extract and cache metadata (runs in background, doesn't block)
            await extractAndCacheMetadata()
        } catch {
            print("Error loading duration: \(error)")
        }
    }
    
    private func setupThumbnailGenerator() {
        // Use proxy asset for faster thumbnail generation
        let generator = AVAssetImageGenerator(asset: proxyAsset)
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
        // Use proxy asset for faster thumbnail generation
        let imageGenerator = AVAssetImageGenerator(asset: proxyAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Generate at higher resolution for Retina displays
        let scale = UIScreen.main.scale
        imageGenerator.maximumSize = CGSize(
            width: 200 * scale,
            height: 112 * scale
        ) // 16:9 aspect ratio thumbnail
        
        do {
            let duration = try await proxyAsset.load(.duration)
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
        // CRITICAL: Use original asset for full quality export, not proxy
        let imageGenerator = AVAssetImageGenerator(asset: originalAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        // No maximumSize constraint = full resolution export
        
        do {
            let cgImage = try await imageGenerator.image(at: currentTime).image
            return UIImage(cgImage: cgImage)
        } catch {
            print("Error capturing frame: \(error)")
            return nil
        }
    }
    
    // MARK: - Metadata Extraction (Streamlined)
    
    /// Target metadata fields we want to extract
    /// Note: Lens-specific fields (lensModel, fNumber, iso, etc.) are rarely present in iPhone videos
    /// as these values change per-frame during recording. They're only reliably available in photos.
    private static let targetFields: Set<String> = [
        "make", "model", "software", "creationDate", "location",
        "lensModel", "focalLength", "focalLength35mm", "fNumber", "iso", "exposureTime"
    ]
    
    /// Extract and cache metadata once when video loads
    private func extractAndCacheMetadata() async {
        let metadata = await extractVideoMetadataOnce()
        cachedVideoMetadata = metadata
        cachedImageMetadata = buildImageMetadata(from: metadata)
    }
    
    /// Get cached video metadata (instant, no async needed after initial load)
    func getVideoMetadata() -> [String: Any] {
        return cachedVideoMetadata ?? [:]
    }
    
    /// Get cached image metadata ready for EXIF embedding (instant access)
    func getImageMetadata() -> [String: Any] {
        return cachedImageMetadata ?? [:]
    }
    
    /// Single-pass metadata extraction with early exit
    private func extractVideoMetadataOnce() async -> [String: Any] {
        var metadata: [String: Any] = [:]
        var foundFields = Set<String>()
        
        // Helper to check if we've found all fields
        func allFieldsFound() -> Bool {
            foundFields.count >= Self.targetFields.count
        }
        
        do {
            // Load common metadata and creation date in one call
            let (commonMetadata, creationDate) = try await originalAsset.load(.commonMetadata, .creationDate)
            
            // Add creation date
            if let creationDate = creationDate {
                metadata["creationDate"] = creationDate
                foundFields.insert("creationDate")
            }
            
            // Process common metadata (make, model, software)
            for item in commonMetadata {
                if allFieldsFound() { break }
                
                if let commonKey = item.commonKey {
                    switch commonKey {
                    case .commonKeyMake:
                        if let make = try? await item.load(.stringValue), metadata["make"] == nil {
                            metadata["make"] = make
                            foundFields.insert("make")
                        }
                    case .commonKeyModel:
                        if let model = try? await item.load(.stringValue), metadata["model"] == nil {
                            metadata["model"] = model
                            foundFields.insert("model")
                        }
                    case .commonKeySoftware:
                        if let software = try? await item.load(.stringValue), metadata["software"] == nil {
                            metadata["software"] = software
                            foundFields.insert("software")
                        }
                    default:
                        break
                    }
                }
            }
            
            // Single pass through all metadata for remaining fields
            let allMetadata = try await originalAsset.load(.metadata)
            
            for item in allMetadata {
                if allFieldsFound() { break }
                
                // Check by identifier first (faster)
                if let identifier = item.identifier {
                    switch identifier {
                    case .quickTimeMetadataLocationISO6709:
                        if metadata["location"] == nil,
                           let locationString = try? await item.load(.stringValue),
                           let location = parseISO6709Location(locationString) {
                            metadata["location"] = location
                            foundFields.insert("location")
                        }
                    case .quickTimeMetadataMake, .commonIdentifierMake:
                        if metadata["make"] == nil,
                           let make = try? await item.load(.stringValue) {
                            metadata["make"] = make
                            foundFields.insert("make")
                        }
                    case .quickTimeMetadataModel, .commonIdentifierModel:
                        if metadata["model"] == nil,
                           let model = try? await item.load(.stringValue) {
                            metadata["model"] = model
                            foundFields.insert("model")
                        }
                    case .quickTimeMetadataSoftware, .commonIdentifierSoftware:
                        if metadata["software"] == nil,
                           let software = try? await item.load(.stringValue) {
                            metadata["software"] = software
                            foundFields.insert("software")
                        }
                    default:
                        break
                    }
                }
                
                // Check by key for lens/camera-specific metadata
                if let key = getKeyString(from: item) {
                    let keyLower = key.lowercased()
                    
                    // Lens model
                    if metadata["lensModel"] == nil &&
                       (keyLower.contains("lens") && keyLower.contains("model") ||
                        key == "com.apple.quicktime.camera.lens_model") {
                        if let value = try? await item.load(.stringValue) {
                            metadata["lensModel"] = value
                            foundFields.insert("lensModel")
                        }
                    }
                    
                    // Focal length 35mm
                    if metadata["focalLength35mm"] == nil &&
                       (keyLower.contains("focal") && keyLower.contains("35mm") ||
                        key == "com.apple.quicktime.camera.focal_length.35mm_equivalent") {
                        if let value = try? await item.load(.numberValue) {
                            metadata["focalLength35mm"] = value
                            foundFields.insert("focalLength35mm")
                        }
                    }
                    
                    // Focal length actual
                    if metadata["focalLength"] == nil &&
                       keyLower.contains("focallength") && !keyLower.contains("35mm") {
                        if let value = try? await item.load(.numberValue) {
                            metadata["focalLength"] = value
                            foundFields.insert("focalLength")
                        }
                    }
                    
                    // F-number / aperture
                    if metadata["fNumber"] == nil &&
                       (keyLower.contains("fnumber") || keyLower.contains("aperture")) {
                        if let value = try? await item.load(.numberValue) {
                            metadata["fNumber"] = value
                            foundFields.insert("fNumber")
                        }
                    }
                    
                    // ISO
                    if metadata["iso"] == nil &&
                       keyLower.contains("iso") && !keyLower.contains("isod") {
                        if let value = try? await item.load(.numberValue) {
                            metadata["iso"] = value
                            foundFields.insert("iso")
                        }
                    }
                    
                    // Exposure time
                    if metadata["exposureTime"] == nil &&
                       (keyLower.contains("exposure") || keyLower.contains("shutter")) {
                        if let value = try? await item.load(.numberValue) {
                            metadata["exposureTime"] = value
                            foundFields.insert("exposureTime")
                        }
                    }
                }
            }
            
            // If we still haven't found lens info, check format-specific metadata
            // Lens data is often in QuickTime MDTA format specifically
            if metadata["lensModel"] == nil {
                let metadataFormats = try await originalAsset.load(.availableMetadataFormats)
                
                for format in metadataFormats {
                    if allFieldsFound() { break }
                    
                    let formatMetadata = try await originalAsset.loadMetadata(for: format)
                    for item in formatMetadata {
                        if let key = getKeyString(from: item) {
                            let keyLower = key.lowercased()
                            
                            // Lens model
                            if metadata["lensModel"] == nil &&
                               (keyLower.contains("lens") && keyLower.contains("model") ||
                                key == "com.apple.quicktime.camera.lens_model") {
                                if let value = try? await item.load(.stringValue) {
                                    metadata["lensModel"] = value
                                    foundFields.insert("lensModel")
                                }
                            }
                            
                            // Focal length 35mm
                            if metadata["focalLength35mm"] == nil &&
                               (keyLower.contains("focal") && keyLower.contains("35mm") ||
                                key == "com.apple.quicktime.camera.focal_length.35mm_equivalent") {
                                if let value = try? await item.load(.numberValue) {
                                    metadata["focalLength35mm"] = value
                                    foundFields.insert("focalLength35mm")
                                }
                            }
                            
                            // F-number / aperture
                            if metadata["fNumber"] == nil &&
                               (keyLower.contains("fnumber") || keyLower.contains("aperture")) {
                                if let value = try? await item.load(.numberValue) {
                                    metadata["fNumber"] = value
                                    foundFields.insert("fNumber")
                                }
                            }
                            
                            // ISO
                            if metadata["iso"] == nil &&
                               keyLower.contains("iso") && !keyLower.contains("isod") {
                                if let value = try? await item.load(.numberValue) {
                                    metadata["iso"] = value
                                    foundFields.insert("iso")
                                }
                            }
                        }
                    }
                }
            }
            
        } catch {
            print("Error extracting metadata: \(error)")
        }
        
        return metadata
    }
    
    /// Convert metadata item key to string
    private func getKeyString(from item: AVMetadataItem) -> String? {
        if let key = item.key as? String {
            return key
        } else if let keyData = item.key as? Data {
            return String(data: keyData, encoding: .utf8)
        } else if let keyNumber = item.key as? NSNumber {
            // FourCC integer to string
            let fourCC = keyNumber.uint32Value
            let chars = [
                Character(UnicodeScalar((fourCC >> 24) & 0xFF)!),
                Character(UnicodeScalar((fourCC >> 16) & 0xFF)!),
                Character(UnicodeScalar((fourCC >> 8) & 0xFF)!),
                Character(UnicodeScalar(fourCC & 0xFF)!)
            ]
            return String(chars)
        }
        return nil
    }
    
    /// Parse ISO 6709 location string format (e.g., "+34.0522-118.2437+025.000/")
    private func parseISO6709Location(_ locationString: String) -> CLLocation? {
        // ISO 6709 format: ±DD.DDDD±DDD.DDDD±AAA.AAA/
        // Latitude (±DD.DDDD) + Longitude (±DDD.DDDD) + optional Altitude (±AAA.AAA) + terminator (/)
        
        let pattern = "([+-]\\d+\\.?\\d*)([+-]\\d+\\.?\\d*)([+-]\\d+\\.?\\d*)?"
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: locationString, range: NSRange(locationString.startIndex..., in: locationString)) else {
            return nil
        }
        
        guard let latRange = Range(match.range(at: 1), in: locationString),
              let lonRange = Range(match.range(at: 2), in: locationString),
              let latitude = Double(locationString[latRange]),
              let longitude = Double(locationString[lonRange]) else {
            return nil
        }
        
        var altitude: Double = 0
        if match.range(at: 3).location != NSNotFound,
           let altRange = Range(match.range(at: 3), in: locationString),
           let alt = Double(locationString[altRange]) {
            altitude = alt
        }
        
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            timestamp: Date()
        )
    }
    
    /// Build EXIF/image metadata dictionary from video metadata
    func buildImageMetadata(from videoMetadata: [String: Any]) -> [String: Any] {
        var imageMetadata: [String: Any] = [:]
        
        // TIFF metadata
        var tiffDict: [String: Any] = [:]
        if let make = videoMetadata["make"] as? String {
            tiffDict[kCGImagePropertyTIFFMake as String] = make
        }
        if let model = videoMetadata["model"] as? String {
            tiffDict[kCGImagePropertyTIFFModel as String] = model
        }
        if let software = videoMetadata["software"] as? String {
            tiffDict[kCGImagePropertyTIFFSoftware as String] = software
        }
        if !tiffDict.isEmpty {
            imageMetadata[kCGImagePropertyTIFFDictionary as String] = tiffDict
        }
        
        // EXIF metadata
        var exifDict: [String: Any] = [:]
        if let creationDate = videoMetadata["creationDate"] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            exifDict[kCGImagePropertyExifDateTimeOriginal as String] = formatter.string(from: creationDate)
            exifDict[kCGImagePropertyExifDateTimeDigitized as String] = formatter.string(from: creationDate)
        }
        
        // Lens model
        if let lensModel = videoMetadata["lensModel"] as? String {
            exifDict[kCGImagePropertyExifLensModel as String] = lensModel
        }
        
        // Lens make (typically same as camera make for iPhones)
        if let make = videoMetadata["make"] as? String {
            exifDict[kCGImagePropertyExifLensMake as String] = make
        }
        
        // Focal length in 35mm equivalent
        if let focalLength35mm = videoMetadata["focalLength35mm"] as? NSNumber {
            exifDict[kCGImagePropertyExifFocalLenIn35mmFilm as String] = focalLength35mm.intValue
        }
        
        // Focal length (actual)
        if let focalLength = videoMetadata["focalLength"] as? NSNumber {
            exifDict[kCGImagePropertyExifFocalLength as String] = focalLength.doubleValue
        }
        
        // F-number (aperture)
        if let fNumber = videoMetadata["fNumber"] as? NSNumber {
            exifDict[kCGImagePropertyExifFNumber as String] = fNumber.doubleValue
        }
        
        // ISO speed
        if let iso = videoMetadata["iso"] as? NSNumber {
            exifDict[kCGImagePropertyExifISOSpeedRatings as String] = [iso.intValue]
        }
        
        // Exposure time
        if let exposureTime = videoMetadata["exposureTime"] as? NSNumber {
            exifDict[kCGImagePropertyExifExposureTime as String] = exposureTime.doubleValue
        }
        
        if !exifDict.isEmpty {
            imageMetadata[kCGImagePropertyExifDictionary as String] = exifDict
        }
        
        // GPS metadata
        if let location = videoMetadata["location"] as? CLLocation {
            var gpsDict: [String: Any] = [:]
            
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            
            gpsDict[kCGImagePropertyGPSLatitude as String] = abs(latitude)
            gpsDict[kCGImagePropertyGPSLatitudeRef as String] = latitude >= 0 ? "N" : "S"
            gpsDict[kCGImagePropertyGPSLongitude as String] = abs(longitude)
            gpsDict[kCGImagePropertyGPSLongitudeRef as String] = longitude >= 0 ? "E" : "W"
            
            if location.altitude != 0 {
                gpsDict[kCGImagePropertyGPSAltitude as String] = abs(location.altitude)
                gpsDict[kCGImagePropertyGPSAltitudeRef as String] = location.altitude >= 0 ? 0 : 1
            }
            
            imageMetadata[kCGImagePropertyGPSDictionary as String] = gpsDict
        }
        
        return imageMetadata
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

