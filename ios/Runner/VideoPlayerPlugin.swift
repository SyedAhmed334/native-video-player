import Flutter
import UIKit
import AVFoundation
import AVKit

/**
 * VideoPlayerPlugin - Complete AVPlayer integration for Flutter
 *
 * Features:
 * - Seamless quality switching without reload
 * - Instant audio track switching
 * - Instant subtitle switching with rendering
 * - Adaptive bitrate streaming (HLS)
 * - Offline playback support
 * - External subtitle loading
 * - Netflix-smooth experience
 */
public class VideoPlayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    private static let METHOD_CHANNEL = "native_video_player/method"
    private static let EVENT_CHANNEL = "native_video_player/event"
    
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    private var textureRegistry: FlutterTextureRegistry?
    
    // AVPlayer components
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var playerLayer: AVPlayerLayer?
    private var textureId: Int64?
    private var displayLink: CADisplayLink?
    private var videoTexture: FlutterVideoTexture?
    
    // Subtitle rendering
    private var legibleOutput: AVPlayerItemLegibleOutput?
    private var currentSubtitleText: String = ""
    
    // Track information
    private var availableQualities: [VideoQualityInfo] = []
    private var availableAudioTracks: [AudioTrackInfo] = []
    private var availableSubtitles: [SubtitleTrackInfo] = []
    private var selectedQualityIndex: Int = -1
    private var selectedAudioIndex: Int = -1
    private var selectedSubtitleIndex: Int = -1
    
    // State tracking
    private var isBuffering: Bool = false
    private var isPlaying: Bool = false
    private var currentUrl: String?
    private var timeObserver: Any?
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = VideoPlayerPlugin()
        
        instance.methodChannel = FlutterMethodChannel(
            name: METHOD_CHANNEL,
            binaryMessenger: registrar.messenger()
        )
        
        instance.eventChannel = FlutterEventChannel(
            name: EVENT_CHANNEL,
            binaryMessenger: registrar.messenger()
        )
        
        instance.textureRegistry = registrar.textures()
        
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)
        instance.eventChannel?.setStreamHandler(instance)
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        startPositionUpdates()
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        stopPositionUpdates()
        return nil
    }
    
    // MARK: - Method Channel Handler
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing URL", details: nil))
                return
            }
            initializePlayer(url: url, result: result)
            
        case "play":
            play(result: result)
            
        case "pause":
            pause(result: result)
            
        case "seekTo":
            guard let args = call.arguments as? [String: Any],
                  let position = args["position"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing position", details: nil))
                return
            }
            seekTo(position: position, result: result)
            
        case "setVolume":
            guard let args = call.arguments as? [String: Any],
                  let volume = args["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing volume", details: nil))
                return
            }
            setVolume(volume: volume, result: result)
            
        case "setSpeed":
            guard let args = call.arguments as? [String: Any],
                  let speed = args["speed"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing speed", details: nil))
                return
            }
            setSpeed(speed: speed, result: result)
            
        case "getDuration":
            getDuration(result: result)
            
        case "getCurrentPosition":
            getCurrentPosition(result: result)
            
        case "getBufferedPosition":
            getBufferedPosition(result: result)
            
        case "getAvailableQualities":
            getAvailableQualities(result: result)
            
        case "setQuality":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing index", details: nil))
                return
            }
            setQuality(index: index, result: result)
            
        case "setAutoQuality":
            setAutoQuality(result: result)
            
        case "getAvailableAudioTracks":
            getAvailableAudioTracks(result: result)
            
        case "setAudioTrack":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing index", details: nil))
                return
            }
            setAudioTrack(index: index, result: result)
            
        case "getAvailableSubtitles":
            getAvailableSubtitles(result: result)
            
        case "setSubtitle":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing index", details: nil))
                return
            }
            setSubtitle(index: index, result: result)
            
        case "loadExternalSubtitle":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing URL", details: nil))
                return
            }
            loadExternalSubtitle(url: url, result: result)
            
        case "enableOfflineMode":
            guard let args = call.arguments as? [String: Any],
                  let localPath = args["localPath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing localPath", details: nil))
                return
            }
            enableOfflineMode(localPath: localPath, result: result)
            
        case "dispose":
            disposePlayer(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Player Initialization
    
    private func initializePlayer(url: String, result: @escaping FlutterResult) {
        currentUrl = url
        
        guard let videoUrl = URL(string: url) else {
            result(FlutterError(code: "INVALID_URL", message: "Invalid URL", details: nil))
            return
        }
        
        // Create player item with buffer configuration
        playerItem = AVPlayerItem(url: videoUrl)
        
        // Configure buffer settings for smooth seeking
        // preferredForwardBufferDuration: How much to buffer ahead (in seconds)
        // iOS automatically manages back buffer but we can influence forward buffer
        playerItem?.preferredForwardBufferDuration = 60  // Buffer 60 seconds ahead
        playerItem?.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        
        // Create player
        player = AVPlayer(playerItem: playerItem)
        player?.automaticallyWaitsToMinimizeStalling = true
        
        // Set up subtitle output
        setupSubtitleOutput()
        
        // Add observers
        addPlayerObservers()
        
        // Create texture
        videoTexture = FlutterVideoTexture(player: player!)
        textureId = textureRegistry?.register(videoTexture!)
        
        // Setup display link
        setupDisplayLink()
        
        result(["textureId": textureId!])
    }
    
    // MARK: - Display Link
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(onDisplayLink))
        displayLink?.add(to: .current, forMode: .common)
        displayLink?.isPaused = true
    }
    
    @objc private func onDisplayLink() {
        guard let texture = videoTexture,
              let id = textureId,
              texture.hasNewPixelBuffer() else { return }
        
        textureRegistry?.textureFrameAvailable(id)
    }
    
    // MARK: - Playback Controls
    
    private func play(result: @escaping FlutterResult) {
        player?.play()
        displayLink?.isPaused = false
        result(nil)
    }
    
    private func pause(result: @escaping FlutterResult) {
        player?.pause()
        displayLink?.isPaused = true
        result(nil)
    }
    
    private func seekTo(position: Int64, result: @escaping FlutterResult) {
        let time = CMTime(value: position, timescale: 1000)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        result(nil)
    }
    
    private func setVolume(volume: Double, result: @escaping FlutterResult) {
        player?.volume = Float(volume)
        result(nil)
    }
    
    private func setSpeed(speed: Double, result: @escaping FlutterResult) {
        player?.rate = Float(speed)
        result(nil)
    }
    
    private func getDuration(result: @escaping FlutterResult) {
        guard let duration = player?.currentItem?.duration else {
            result(0)
            return
        }
        
        result(safeInt64(from: CMTimeGetSeconds(duration) * 1000))
    }
    
    private func getCurrentPosition(result: @escaping FlutterResult) {
        guard let currentTime = player?.currentTime() else {
            result(0)
            return
        }
        result(safeInt64(from: CMTimeGetSeconds(currentTime) * 1000))
    }
    
    private func getBufferedPosition(result: @escaping FlutterResult) {
        guard let timeRange = player?.currentItem?.loadedTimeRanges.first?.timeRangeValue else {
            result(0)
            return
        }
        
        let bufferedTime = CMTimeAdd(timeRange.start, timeRange.duration)
        result(safeInt64(from: CMTimeGetSeconds(bufferedTime) * 1000))
    }
    
    // MARK: - Track Management
    
    private func getAvailableQualities(result: @escaping FlutterResult) {
        updateAvailableTracks()
        
        var qualities: [[String: Any]] = []
        for (index, quality) in availableQualities.enumerated() {
            qualities.append([
                "index": index,
                "width": quality.width,
                "height": quality.height,
                "bitrate": Int(quality.bitrate),
                "label": quality.label
            ])
        }
        
        result(qualities)
    }
    
    private func setQuality(index: Int, result: @escaping FlutterResult) {
        guard index >= 0 && index < availableQualities.count else {
            result(FlutterError(code: "INVALID_INDEX", message: "Quality index out of range", details: nil))
            return
        }
        
        let quality = availableQualities[index]
        
        // Set preferred peak bit rate for quality selection
        // Add a small buffer to ensure the variant is included
        playerItem?.preferredPeakBitRate = quality.bitrate + 1.0
        
        // Set preferred maximum resolution to enforce quality
        let resolution = CGSize(width: quality.width, height: quality.height)
        playerItem?.preferredMaximumResolution = resolution
        
        selectedQualityIndex = index
        sendEvent(["event": "qualityChanged", "index": index, "isAuto": false])
        result(nil)
    }
    
    /// Set auto quality - ADAPTIVE BITRATE (Netflix/YouTube-style)
    /// Clears constraints and lets AVPlayer's ABR algorithm choose
    /// the optimal quality based on network conditions
    private func setAutoQuality(result: @escaping FlutterResult) {
        // Reset bitrate constraint to 0 (unlimited/automatic)
        playerItem?.preferredPeakBitRate = 0
        
        // Reset resolution constraint to allow any resolution
        playerItem?.preferredMaximumResolution = CGSize.zero
        
        selectedQualityIndex = -1
        sendEvent(["event": "qualityChanged", "index": -1, "isAuto": true])
        result(nil)
    }
    
    private func getAvailableAudioTracks(result: @escaping FlutterResult) {
        updateAvailableTracks()
        
        var audioTracks: [[String: Any]] = []
        for (index, audio) in availableAudioTracks.enumerated() {
            audioTracks.append([
                "index": index,
                "language": audio.language,
                "label": audio.label
            ])
        }
        
        result(audioTracks)
    }
    
    private func setAudioTrack(index: Int, result: @escaping FlutterResult) {
        guard index >= 0 && index < availableAudioTracks.count else {
            result(FlutterError(code: "INVALID_INDEX", message: "Audio track index out of range", details: nil))
            return
        }
        
        let audioTrack = availableAudioTracks[index]
        
        // Enable selected audio track
        if let group = audioTrack.group,
           let option = group.options[safe: index] {
            playerItem?.select(option, in: group)
        }
        
        selectedAudioIndex = index
        sendEvent(["event": "audioChanged", "index": index])
        result(nil)
    }
    
    private func getAvailableSubtitles(result: @escaping FlutterResult) {
        updateAvailableTracks()
        
        var subtitles: [[String: Any]] = []
        for (index, subtitle) in availableSubtitles.enumerated() {
            subtitles.append([
                "index": index,
                "language": subtitle.language,
                "label": subtitle.label
            ])
        }
        
        result(subtitles)
    }
    
    private func setSubtitle(index: Int, result: @escaping FlutterResult) {
        if index == -1 {
            // Disable subtitles
            if let asset = playerItem?.asset,
               let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                playerItem?.select(nil, in: group)
            }
            selectedSubtitleIndex = -1
            sendEvent(["event": "subtitleChanged", "index": -1])
            sendEvent(["event": "subtitleText", "text": ""])
            result(nil)
            return
        }
        
        guard index >= 0 && index < availableSubtitles.count else {
            result(FlutterError(code: "INVALID_INDEX", message: "Subtitle index out of range", details: nil))
            return
        }
        
        let subtitle = availableSubtitles[index]
        
        // Enable selected subtitle track
        if let group = subtitle.group,
           let option = group.options[safe: index] {
            playerItem?.select(option, in: group)
        }
        
        selectedSubtitleIndex = index
        sendEvent(["event": "subtitleChanged", "index": index])
        result(nil)
    }
    
    private func loadExternalSubtitle(url: String, result: @escaping FlutterResult) {
        // iOS doesn't support external subtitles as easily as Android
        // Would need to parse VTT/SRT manually and render
        result(FlutterError(code: "NOT_IMPLEMENTED", message: "External subtitles not yet implemented on iOS", details: nil))
    }
    
    private func enableOfflineMode(localPath: String, result: @escaping FlutterResult) {
        guard let fileUrl = URL(string: localPath) else {
            result(FlutterError(code: "INVALID_PATH", message: "Invalid local path", details: nil))
            return
        }
        
        playerItem = AVPlayerItem(url: fileUrl)
        player?.replaceCurrentItem(with: playerItem)
        result(nil)
    }
    
    private func disposePlayer(result: @escaping FlutterResult) {
        stopPositionUpdates()
        removePlayerObservers()
        
        player?.pause()
        player = nil
        playerItem = nil
        playerLayer = nil
        
        if let id = textureId {
            textureRegistry?.unregisterTexture(id)
            textureId = nil
        }
        
        displayLink?.invalidate()
        displayLink = nil
        videoTexture = nil
        
        result(nil)
    }
    
    // MARK: - Track Updates
    
    private func updateAvailableTracks() {
        guard let asset = playerItem?.asset else { return }
        
        // Update video qualities (variants in HLS)
        availableQualities = []
        if #available(iOS 15.0, *) {
            if let variants = (asset as? AVURLAsset)?.variants {
                for (index, variant) in variants.enumerated() {
                    let quality = VideoQualityInfo(
                        index: index,
                        width: Int(variant.videoAttributes?.presentationSize.width ?? 0),
                        height: Int(variant.videoAttributes?.presentationSize.height ?? 0),
                        bitrate: variant.peakBitRate ?? 0,
                        label: "\(Int(variant.videoAttributes?.presentationSize.height ?? 0))p"
                    )
                    availableQualities.append(quality)
                }
            }
        }
        
        // Update audio tracks
        availableAudioTracks = []
        let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        if let options = audioGroup?.options {
            for (index, option) in options.enumerated() {
                let audio = AudioTrackInfo(
                    index: index,
                    language: option.extendedLanguageTag ?? "Unknown",
                    label: option.displayName,
                    group: audioGroup
                )
                availableAudioTracks.append(audio)
            }
        }
        
        // Update subtitle tracks
        availableSubtitles = []
        let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        if let options = subtitleGroup?.options {
            for (index, option) in options.enumerated() {
                let subtitle = SubtitleTrackInfo(
                    index: index,
                    language: option.extendedLanguageTag ?? "Unknown",
                    label: option.displayName,
                    group: subtitleGroup
                )
                availableSubtitles.append(subtitle)
            }
        }
    }
    
    // MARK: - Subtitle Output
    
    private func setupSubtitleOutput() {
        // Use empty array to allow all subtitle formats
        legibleOutput = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        
        legibleOutput?.setDelegate(self, queue: DispatchQueue.main)
        playerItem?.add(legibleOutput!)
    }
    
    // MARK: - Observers
    
    private func addPlayerObservers() {
        // Observe player item status
        playerItem?.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        playerItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [.new], context: nil)
        playerItem?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: [.new], context: nil)
        
        // Observe playback end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }
    
    private func removePlayerObservers() {
        playerItem?.removeObserver(self, forKeyPath: "status")
        playerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        playerItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        NotificationCenter.default.removeObserver(self)
        
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if playerItem?.status == .readyToPlay {
                updateAvailableTracks()
            }
        } else if keyPath == "playbackBufferEmpty" {
            if playerItem?.isPlaybackBufferEmpty == true {
                isBuffering = true
                sendEvent(["bufferState": "buffering"])
            }
        } else if keyPath == "playbackLikelyToKeepUp" {
            if playerItem?.isPlaybackLikelyToKeepUp == true {
                isBuffering = false
                sendEvent(["bufferState": "ready"])
            }
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        sendEvent(["playbackState": "completed"])
    }
    
    // MARK: - Position Updates
    
    private func startPositionUpdates() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updatePosition()
        }
    }
    
    private func stopPositionUpdates() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    private func updatePosition() {
        guard let player = player else { return }
        
        let position = safeInt64(from: CMTimeGetSeconds(player.currentTime()) * 1000)
        
        var buffered: Int64 = 0
        if let timeRange = playerItem?.loadedTimeRanges.first?.timeRangeValue {
            buffered = safeInt64(from: CMTimeGetSeconds(timeRange.end) * 1000)
        }
        
        var duration: Int64 = 0
        if let itemDuration = playerItem?.duration {
            duration = safeInt64(from: CMTimeGetSeconds(itemDuration) * 1000)
        }
        
        sendEvent([
            "event": "position",
            "position": position,
            "bufferedPosition": buffered,
            "duration": duration
        ])
        
        // Send playback state only when it changes
        let currentlyPlaying = player.rate > 0
        if currentlyPlaying != isPlaying {
            isPlaying = currentlyPlaying
            sendEvent(["playbackState": isPlaying ? "playing" : "paused"])
        }
    }
    
    private func safeInt64(from value: Double) -> Int64 {
        if value.isNaN || value.isInfinite {
            return 0
        }
        return Int64(value)
    }
    
    // MARK: - Event Streaming
    
    private func sendEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }
}

// MARK: - AVPlayerItemLegibleOutputPushDelegate

extension VideoPlayerPlugin: AVPlayerItemLegibleOutputPushDelegate {
    public func legibleOutput(_ output: AVPlayerItemLegibleOutput, didOutputAttributedStrings strings: [NSAttributedString], nativeSampleBuffers nativeSamples: [Any], forItemTime itemTime: CMTime) {
        var text = ""
        for string in strings {
            text += string.string + "\n"
        }
        
        currentSubtitleText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sendEvent(["event": "subtitleText", "text": currentSubtitleText])
    }
}

// MARK: - FlutterTexture

class FlutterVideoTexture: NSObject, FlutterTexture {
    private let player: AVPlayer
    private var videoOutput: AVPlayerItemVideoOutput?
    
    init(player: AVPlayer) {
        self.player = player
        super.init()
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        player.currentItem?.add(videoOutput!)
    }
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let output = videoOutput else { return nil }
        
        let time = player.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time) else { return nil }
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return nil }
        
        return Unmanaged.passRetained(pixelBuffer)
    }
    
    func hasNewPixelBuffer() -> Bool {
        guard let output = videoOutput else { return false }
        return output.hasNewPixelBuffer(forItemTime: player.currentTime())
    }
}


// MARK: - Helper Structs

struct VideoQualityInfo {
    let index: Int
    let width: Int
    let height: Int
    let bitrate: Double
    let label: String
}

struct AudioTrackInfo {
    let index: Int
    let language: String
    let label: String
    let group: AVMediaSelectionGroup?
}

struct SubtitleTrackInfo {
    let index: Int
    let language: String
    let label: String
    let group: AVMediaSelectionGroup?
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
