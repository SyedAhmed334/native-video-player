import Foundation
import AVFoundation
import AVKit
import Flutter

/// VideoPlayerInstance - Encapsulates a single AVPlayer instance
/// Each instance has its own player, texture, and event sink
class VideoPlayerInstance: NSObject {
    let playerId: String
    private let textureRegistry: FlutterTextureRegistry
    
    // Player components
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var flutterTexture: FlutterVideoTexture?
    private var textureId: Int64?
    private var displayLink: CADisplayLink?
    
    // PiP support
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    
    // Event sink
    var eventSink: FlutterEventSink?
    
    // Observers
    private var playerObservers: [NSKeyValueObservation] = []
    
    // Subtitle output
    private var legibleOutput: AVPlayerItemLegibleOutput?
    private var timeObserver: Any?
    
    // Track information
    private var availableQualities: [VideoQualityInfo] = []
    private var availableAudioTracks: [AudioTrackInfo] = []
    private var availableSubtitles: [SubtitleTrackInfo] = []
    private var selectedQualityIndex: Int = -1
    private var selectedAudioIndex: Int = -1
    private var selectedSubtitleIndex: Int = -1
    private var isAutoQuality = true
    
    // State
    private var currentUrl: String?
    private var duration: Double = 0
    private var isDisposed = false
    
    // Lock for thread safety
    private let lock = NSLock()
    
    init(playerId: String, textureRegistry: FlutterTextureRegistry) {
        self.playerId = playerId
        self.textureRegistry = textureRegistry
        super.init()
    }
    
    /// Check if player is disposed
    func isPlayerDisposed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isDisposed
    }
    
    // MARK: - Initialization
    
    func initialize(url: String) -> Int64 {
        lock.lock()
        if isDisposed {
            lock.unlock()
            print("[VideoPlayerInstance:\(playerId)] Cannot initialize - player is disposed")
            return -1
        }
        lock.unlock()
        
        currentUrl = url
        
        guard let videoURL = URL(string: url) else {
            print("[VideoPlayerInstance:\(playerId)] Invalid URL: \(url)")
            sendEvent(["event": "error", "message": "Invalid URL"])
            return -1
        }
        
        do {
        // Check for cached file
        var targetURL = videoURL
        if let cachedFile = VideoCacheManager.shared.getCachedFile(for: url) {
            print("[VideoPlayerInstance:\(playerId)] Playing from cache: \(cachedFile.lastPathComponent)")
            targetURL = cachedFile
        } else {
            print("[VideoPlayerInstance:\(playerId)] Playing from network: \(url)")
        }
        

            // Create player
            playerItem = AVPlayerItem(url: targetURL)
            player = AVPlayer(playerItem: playerItem)
            
            guard let player = player else {
                print("[VideoPlayerInstance:\(playerId)] Failed to create AVPlayer")
                sendEvent(["event": "error", "message": "Failed to create player"])
                return -1
            }
            
            // Create Flutter texture
            flutterTexture = FlutterVideoTexture(player: player)
            guard let texture = flutterTexture else {
                print("[VideoPlayerInstance:\(playerId)] Failed to create texture")
                sendEvent(["event": "error", "message": "Failed to create texture"])
                return -1
            }
            
            textureId = textureRegistry.register(texture)
            
            // Setup observers
            setupObservers()
            setupDisplayLink()
            setupSubtitleOutput()
            
            // Configure audio session
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            print("[VideoPlayerInstance:\(playerId)] Initialized with texture: \(textureId ?? -1)")
            return textureId ?? -1
        } catch {
            print("[VideoPlayerInstance:\(playerId)] Initialization error: \(error)")
            sendEvent(["event": "error", "message": "Initialization error: \(error.localizedDescription)"])
            dispose()
            return -1
        }
    }
    
    /// Initialize with FairPlay DRM protected content
    /// - Parameters:
    ///   - url: HLS URL with FairPlay encryption
    ///   - licenseUrl: FairPlay license server URL
    ///   - certificateUrl: FairPlay application certificate URL
    ///   - headers: Optional headers for license requests
    /// - Returns: Texture ID for Flutter rendering, or -1 on failure
    func initializeWithDrm(
        url: String,
        licenseUrl: String,
        certificateUrl: String,
        headers: [String: String]?
    ) -> Int64 {
        lock.lock()
        if isDisposed {
            lock.unlock()
            print("[VideoPlayerInstance:\(playerId)] Cannot initialize DRM - player is disposed")
            return -1
        }
        lock.unlock()
        
        currentUrl = url
        
        guard let videoURL = URL(string: url) else {
            print("[VideoPlayerInstance:\(playerId)] Invalid URL: \(url)")
            sendEvent(["event": "error", "message": "Invalid DRM URL"])
            return -1
        }
        
        do {
            // Create asset with DRM content key request handling
            let asset = AVURLAsset(url: videoURL)
            
            // For FairPlay, we need to configure the resource loader delegate
            // This is a simplified implementation - full FairPlay requires:
            // 1. Fetching application certificate from certificateUrl
            // 2. Creating SPC (Server Playback Context)
            // 3. Sending SPC to licenseUrl to get CKC (Content Key Context)
            // 4. Providing CKC back to AVPlayer
            
            // Store DRM configuration for later use in resource loader
            self.drmLicenseUrl = licenseUrl
            self.drmCertificateUrl = certificateUrl
            self.drmHeaders = headers
            
            // Set resource loader delegate for handling FairPlay requests
            asset.resourceLoader.setDelegate(self, queue: DispatchQueue.main)
            
            // Create player item from asset
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem)
            
            guard let player = player else {
                print("[VideoPlayerInstance:\(playerId)] Failed to create AVPlayer for DRM")
                sendEvent(["event": "error", "message": "Failed to create DRM player"])
                return -1
            }
            
            // Create Flutter texture
            flutterTexture = FlutterVideoTexture(player: player)
            guard let texture = flutterTexture else {
                print("[VideoPlayerInstance:\(playerId)] Failed to create DRM texture")
                sendEvent(["event": "error", "message": "Failed to create DRM texture"])
                return -1
            }
            
            textureId = textureRegistry.register(texture)
            
            // Setup observers
            setupObservers()
            setupDisplayLink()
            
            // Configure audio session
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            print("[VideoPlayerInstance:\(playerId)] Initialized with FairPlay DRM, texture: \(textureId ?? -1)")
            sendEvent(["event": "drmInitialized", "type": "fairplay"])
            return textureId ?? -1
        } catch {
            print("[VideoPlayerInstance:\(playerId)] DRM initialization error: \(error)")
            sendEvent(["event": "error", "message": "DRM initialization error: \(error.localizedDescription)"])
            dispose()
            return -1
        }
    }
    
    // DRM configuration storage
    private var drmLicenseUrl: String?
    private var drmCertificateUrl: String?
    private var drmHeaders: [String: String]?
    
    func preload(url: String) -> Int64 {
        // Initialize (will use cache if available)
        let tid = initialize(url: url)
        player?.pause()
        // print("[VideoPlayerInstance:\(playerId)] Preloaded (Instance): \(url)")
        return tid
    }
    
    // MARK: - Playback Control
    
    func play() {
        player?.play()
    }
    
    func pause() {
        player?.pause()
    }
    
    func seekTo(position: Int64) {
        let time = CMTime(milliseconds: position)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func setVolume(volume: Double) {
        player?.volume = Float(volume)
    }
    
    func setSpeed(speed: Double) {
        player?.rate = Float(speed)
    }
    
    func getDuration() -> Int64 {
        guard let item = playerItem else { return 0 }
        let duration = item.duration
        if duration.isIndefinite { return 0 }
        return Int64(CMTimeGetSeconds(duration) * 1000)
    }
    
    func getCurrentPosition() -> Int64 {
        guard let currentTime = player?.currentTime() else { return 0 }
        return Int64(CMTimeGetSeconds(currentTime) * 1000)
    }
    
    func getBufferedPosition() -> Int64 {
        guard let loadedRanges = playerItem?.loadedTimeRanges,
              let first = loadedRanges.first else { return 0 }
        let range = first.timeRangeValue
        let bufferedEnd = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
        return Int64(bufferedEnd * 1000)
    }
    
    // MARK: - Picture-in-Picture
    
    func enterPiP(result: @escaping FlutterResult) {
        // Lazy create player layer if needed
        if playerLayer == nil, let player = player {
            playerLayer = AVPlayerLayer(player: player)
            setupPiP()
        }
        
        guard let pipController = pipController else {
            result(FlutterError(code: "PIP_NOT_READY", message: "PiP controller not initialized", details: nil))
            return
        }
        
        if pipController.isPictureInPicturePossible {
            pipController.startPictureInPicture()
            result(true)
        } else {
            result(FlutterError(code: "PIP_NOT_POSSIBLE", message: "PiP not possible at this time", details: nil))
        }
    }
    
    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("[VideoPlayerInstance:\(playerId)] PiP not supported on this device")
            return
        }
        
        guard let layer = playerLayer else { return }
        
        // PiP requires the layer to be in the view hierarchy
        if let rootViewController = UIApplication.shared.keyWindow?.rootViewController {
            layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            rootViewController.view.layer.addSublayer(layer)
        }
        
        pipController = AVPictureInPictureController(playerLayer: layer)
        pipController?.delegate = self
        
        print("[VideoPlayerInstance:\(playerId)] PiP controller initialized")
    }
    
    // MARK: - Tracks
    
    func getAvailableQualities() -> [[String: Any]] {
        updateAvailableTracks()
        return availableQualities.enumerated().map { index, quality in
            [
                "index": index,
                "width": quality.width,
                "height": quality.height,
                "bitrate": quality.bitrate,
                "label": quality.label
            ]
        }
    }
    
    func setQuality(index: Int) {
        guard index >= 0 && index < availableQualities.count else { return }
        selectedQualityIndex = index
        isAutoQuality = false
        
        // For HLS, quality is handled by preferredPeakBitRate
        let quality = availableQualities[index]
        playerItem?.preferredPeakBitRate = Double(quality.bitrate)
        
        sendEvent([
            "event": "qualityChanged",
            "index": index,
            "isAuto": false
        ])
    }
    
    func setAutoQuality() {
        playerItem?.preferredPeakBitRate = 0
        selectedQualityIndex = -1
        isAutoQuality = true
        
        sendEvent([
            "event": "qualityChanged",
            "index": -1,
            "isAuto": true
        ])
    }
    
    func getAvailableAudioTracks() -> [[String: Any]] {
        updateAvailableTracks()
        return availableAudioTracks.enumerated().map { index, audio in
            [
                "index": index,
                "language": audio.language,
                "label": audio.label
            ]
        }
    }
    
    func setAudioTrack(index: Int) {
        guard index >= 0 && index < availableAudioTracks.count else { return }
        
        let audio = availableAudioTracks[index]
        if let group = audio.group,
           let asset = playerItem?.asset {
            let options = AVMediaSelectionGroup.mediaSelectionOptions(
                from: group.options,
                with: Locale(identifier: audio.language)
            )
            if let option = options.first ?? group.options[safe: index] {
                playerItem?.select(option, in: group)
                selectedAudioIndex = index
                sendEvent(["event": "audioChanged", "index": index])
            }
        }
    }
    
    func getAvailableSubtitles() -> [[String: Any]] {
        updateAvailableTracks()
        return availableSubtitles.enumerated().map { index, subtitle in
            [
                "index": index,
                "language": subtitle.language,
                "label": subtitle.label
            ]
        }
    }
    
    func setSubtitle(index: Int) {
        if index == -1 {
            // Disable subtitles
            if let asset = playerItem?.asset,
               let group = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                playerItem?.select(nil, in: group)
            }
        } else if index >= 0 && index < availableSubtitles.count {
            let subtitle = availableSubtitles[index]
            if let group = subtitle.group,
               let option = group.options[safe: index] {
                playerItem?.select(option, in: group)
            }
        }
        selectedSubtitleIndex = index
        sendEvent(["event": "subtitleChanged", "index": index])
    }
    
    // MARK: - Cleanup
    
    func dispose() {
        lock.lock()
        if isDisposed {
            lock.unlock()
            print("[VideoPlayerInstance:\(playerId)] Already disposed, skipping")
            return
        }
        isDisposed = true
        lock.unlock()
        
        print("[VideoPlayerInstance:\(playerId)] Disposing...")
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self)
        
        // Stop display link
        displayLink?.invalidate()
        displayLink = nil
        
        // Remove observers
        playerObservers.forEach { $0.invalidate() }
        playerObservers.removeAll()
        
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Stop player
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerItem = nil
        
        // Unregister texture
        if let tid = textureId {
            textureRegistry.unregisterTexture(tid)
        }
        flutterTexture = nil
        textureId = nil
        
        // Clear tracks
        availableQualities.removeAll()
        availableAudioTracks.removeAll()
        availableSubtitles.removeAll()
        
        print("[VideoPlayerInstance:\(playerId)] Disposed")
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        guard let item = playerItem, let player = player else { return }
        
        // Status observer
        let statusObserver = item.observe(\.status) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                self.duration = CMTimeGetSeconds(item.duration)
                self.updateAvailableTracks()
            } else if item.status == .failed {
                self.sendEvent([
                    "event": "error",
                    "message": item.error?.localizedDescription ?? "Unknown error"
                ])
            }
        }
        playerObservers.append(statusObserver)
        
        // Time control observer
        let timeControlObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self = self else { return }
            switch player.timeControlStatus {
            case .playing:
                self.sendEvent(["playbackState": "playing"])
            case .paused:
                self.sendEvent(["playbackState": "paused"])
            case .waitingToPlayAtSpecifiedRate:
                self.sendEvent(["bufferState": "buffering"])
            @unknown default:
                break
            }
        }
        playerObservers.append(timeControlObserver)
        
        // Playback buffer observer
        let bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty) { [weak self] item, _ in
            if item.isPlaybackBufferEmpty {
                self?.sendEvent(["bufferState": "buffering"])
            }
        }
        playerObservers.append(bufferEmptyObserver)
        
        let bufferFullObserver = item.observe(\.isPlaybackLikelyToKeepUp) { [weak self] item, _ in
            if item.isPlaybackLikelyToKeepUp {
                self?.sendEvent(["bufferState": "ready"])
            }
        }
        playerObservers.append(bufferFullObserver)
        
        // Position updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, let item = self.playerItem else { return }
            
            let position = Int64(CMTimeGetSeconds(time) * 1000)
            let duration = item.duration.isIndefinite ? 0 : Int64(CMTimeGetSeconds(item.duration) * 1000)
            let buffered = self.getBufferedPosition()
            
            self.sendEvent([
                "event": "position",
                "position": position,
                "bufferedPosition": buffered,
                "duration": duration
            ])
        }
        
        // End notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func setupSubtitleOutput() {
        guard let playerItem = playerItem else { return }
        
        // Create legible output for subtitle text extraction
        legibleOutput = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        legibleOutput?.setDelegate(self, queue: DispatchQueue.main)
        playerItem.add(legibleOutput!)
        
        print("[VideoPlayerInstance:\(playerId)] Subtitle output configured")
    }
    
    @objc private func displayLinkCallback() {
        guard let texture = flutterTexture, let tid = textureId else { return }
        if texture.hasNewPixelBuffer() {
            textureRegistry.textureFrameAvailable(tid)
        }
    }
    
    @objc private func playerDidFinish() {
        sendEvent(["playbackState": "completed"])
    }
    
    private func updateAvailableTracks() {
        guard let asset = playerItem?.asset else { return }
        
        availableQualities.removeAll()
        availableAudioTracks.removeAll()
        availableSubtitles.removeAll()
        
        // For HLS, we provide standard quality options that map to preferredPeakBitRate
        // AVPlayer doesn't expose HLS variants directly, but we can control quality via bitrate
        
        // First, try to get actual video resolution from the track
        var maxHeight = 1080
        var maxWidth = 1920
        
        let videoTracks = asset.tracks(withMediaType: .video)
        if let videoTrack = videoTracks.first {
            let size = videoTrack.naturalSize
            maxHeight = Int(max(size.height, size.width)) // Handle rotated video
            maxWidth = Int(min(size.height, size.width) * 16 / 9)
            print("[VideoPlayerInstance:\(playerId)] Video track size: \(size)")
        }
        
        // Provide standard quality ladder based on detected max resolution
        // These map to preferredPeakBitRate values
        var qualities: [VideoQualityInfo] = []
        
        if maxHeight >= 1080 {
            qualities.append(VideoQualityInfo(index: 0, width: 1920, height: 1080, bitrate: 5000000, label: "1080p"))
        }
        if maxHeight >= 720 {
            qualities.append(VideoQualityInfo(index: qualities.count, width: 1280, height: 720, bitrate: 2500000, label: "720p"))
        }
        if maxHeight >= 480 {
            qualities.append(VideoQualityInfo(index: qualities.count, width: 854, height: 480, bitrate: 1000000, label: "480p"))
        }
        qualities.append(VideoQualityInfo(index: qualities.count, width: 640, height: 360, bitrate: 500000, label: "360p"))
        qualities.append(VideoQualityInfo(index: qualities.count, width: 426, height: 240, bitrate: 250000, label: "240p"))
        
        availableQualities = qualities
        print("[VideoPlayerInstance:\(playerId)] Available qualities: \(qualities.map { $0.label })")
        
        // Audio tracks
        if let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            for (index, option) in audioGroup.options.enumerated() {
                let language = option.locale?.languageCode ?? "Unknown"
                availableAudioTracks.append(AudioTrackInfo(
                    index: index,
                    language: language,
                    label: option.displayName,
                    group: audioGroup
                ))
            }
        }
        
        // Subtitle tracks
        if let subtitleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            for (index, option) in subtitleGroup.options.enumerated() {
                let language = option.locale?.languageCode ?? "Unknown"
                availableSubtitles.append(SubtitleTrackInfo(
                    index: index,
                    language: language,
                    label: option.displayName,
                    group: subtitleGroup
                ))
            }
        }
    }
    
    private func sendEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }
}

// MARK: - CMTime Extension

extension CMTime {
    init(milliseconds: Int64) {
        self = CMTimeMake(value: milliseconds, timescale: 1000)
    }
}

// MARK: - Data Structures

struct VideoQualityInfo {
    let index: Int
    let width: Int
    let height: Int
    let bitrate: Int
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

// MARK: - AVAssetResourceLoaderDelegate for FairPlay

extension VideoPlayerInstance: AVAssetResourceLoaderDelegate {
    
    /// Handle FairPlay content key requests
    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        // Check if this is a FairPlay key request (skd:// scheme)
        guard let url = loadingRequest.request.url,
              url.scheme == "skd" else {
            return false
        }
        
        print("[VideoPlayerInstance:\(playerId)] FairPlay key request for: \(url)")
        
        // Handle FairPlay key request asynchronously
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.handleFairPlayKeyRequest(loadingRequest: loadingRequest, contentId: url.host ?? "")
        }
        
        return true
    }
    
    private func handleFairPlayKeyRequest(loadingRequest: AVAssetResourceLoadingRequest, contentId: String) {
        guard let certificateUrl = drmCertificateUrl,
              let licenseUrl = drmLicenseUrl else {
            print("[VideoPlayerInstance:\(playerId)] Missing DRM configuration")
            loadingRequest.finishLoading(with: NSError(
                domain: "FairPlay",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing DRM configuration"]
            ))
            return
        }
        
        // Step 1: Fetch application certificate
        guard let certURL = URL(string: certificateUrl) else {
            loadingRequest.finishLoading(with: NSError(
                domain: "FairPlay",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid certificate URL"]
            ))
            return
        }
        
        var certRequest = URLRequest(url: certURL)
        drmHeaders?.forEach { certRequest.setValue($1, forHTTPHeaderField: $0) }
        
        URLSession.shared.dataTask(with: certRequest) { [weak self] certData, _, certError in
            guard let self = self else { return }
            
            if let error = certError {
                print("[VideoPlayerInstance:\(self.playerId)] Certificate fetch error: \(error)")
                loadingRequest.finishLoading(with: error)
                return
            }
            
            guard let certificate = certData else {
                loadingRequest.finishLoading(with: NSError(
                    domain: "FairPlay",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "No certificate data"]
                ))
                return
            }
            
            // Step 2: Create SPC (Server Playback Context)
            guard let contentIdData = contentId.data(using: .utf8) else {
                loadingRequest.finishLoading(with: NSError(
                    domain: "FairPlay",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid content ID"]
                ))
                return
            }
            
            do {
                let spc = try loadingRequest.streamingContentKeyRequestData(
                    forApp: certificate,
                    contentIdentifier: contentIdData,
                    options: nil
                )
                
                // Step 3: Send SPC to license server to get CKC
                guard let licURL = URL(string: licenseUrl) else {
                    loadingRequest.finishLoading(with: NSError(
                        domain: "FairPlay",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid license URL"]
                    ))
                    return
                }
                
                var licRequest = URLRequest(url: licURL)
                licRequest.httpMethod = "POST"
                licRequest.httpBody = spc
                licRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                self.drmHeaders?.forEach { licRequest.setValue($1, forHTTPHeaderField: $0) }
                
                URLSession.shared.dataTask(with: licRequest) { ckcData, _, licError in
                    if let error = licError {
                        print("[VideoPlayerInstance:\(self.playerId)] License fetch error: \(error)")
                        loadingRequest.finishLoading(with: error)
                        return
                    }
                    
                    guard let ckc = ckcData else {
                        loadingRequest.finishLoading(with: NSError(
                            domain: "FairPlay",
                            code: -6,
                            userInfo: [NSLocalizedDescriptionKey: "No license data"]
                        ))
                        return
                    }
                    
                    // Step 4: Provide CKC to player
                    loadingRequest.dataRequest?.respond(with: ckc)
                    loadingRequest.finishLoading()
                    print("[VideoPlayerInstance:\(self.playerId)] FairPlay key loaded successfully")
                }.resume()
                
            } catch {
                print("[VideoPlayerInstance:\(self.playerId)] SPC creation error: \(error)")
                loadingRequest.finishLoading(with: error)
            }
        }.resume()
    }
}

// MARK: - AVPlayerItemLegibleOutputPushDelegate for Subtitles

extension VideoPlayerInstance: AVPlayerItemLegibleOutputPushDelegate {
    func legibleOutput(_ output: AVPlayerItemLegibleOutput, didOutputAttributedStrings strings: [NSAttributedString], nativeSampleBuffers nativeSamples: [Any], forItemTime itemTime: CMTime) {
        var text = ""
        for string in strings {
            text += string.string + "\n"
        }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sendEvent(["event": "subtitleText", "text": trimmedText])
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension VideoPlayerInstance: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        sendEvent(["event": "pipChanged", "isActive": true])
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        sendEvent(["event": "pipChanged", "isActive": false])
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[VideoPlayerInstance:\(playerId)] PiP failed: \(error.localizedDescription)")
        sendEvent(["event": "pipError", "message": error.localizedDescription])
    }
}
