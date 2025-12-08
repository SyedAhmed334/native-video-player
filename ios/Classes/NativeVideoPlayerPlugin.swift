import Flutter
import UIKit
import AVFoundation

/// NativeVideoPlayerPlugin - Multi-instance video player plugin for iOS
/// Routes method calls to the correct VideoPlayerInstance based on playerId
public class NativeVideoPlayerPlugin: NSObject, FlutterPlugin {
    
    private static let methodChannelName = "native_video_player/method"
    private static let eventChannelPrefix = "native_video_player/event/"
    
    private var registrar: FlutterPluginRegistrar
    private var textureRegistry: FlutterTextureRegistry
    
    // Multi-instance storage
    private var players: [String: VideoPlayerInstance] = [:]
    private var eventChannels: [String: FlutterEventChannel] = [:]
    
    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        self.textureRegistry = registrar.textures()
        super.init()
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: registrar.messenger())
        let instance = NativeVideoPlayerPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        print("[NativeVideoPlayerPlugin] Registered")
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let playerId = args?["playerId"] as? String
        
        switch call.method {
        case "initialize":
            guard let pid = playerId, let url = args?["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId or url", details: nil))
                return
            }
            
            // Check for DRM configuration
            if let drm = args?["drm"] as? [String: Any],
               let licenseUrl = drm["licenseUrl"] as? String,
               let certificateUrl = drm["certificateUrl"] as? String {
                let headers = drm["headers"] as? [String: String]
                initializeWithDrm(playerId: pid, url: url, licenseUrl: licenseUrl, certificateUrl: certificateUrl, headers: headers, result: result)
            } else {
                initialize(playerId: pid, url: url, result: result)
            }
            
        case "preload":
            guard let pid = playerId, let url = args?["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId or url", details: nil))
                return
            }
            preload(playerId: pid, url: url, result: result)
            
        case "play":
            guard let player = getPlayer(playerId: playerId, result: result) else { return }
            player.play()
            result(nil)
            
        case "pause":
            guard let player = getPlayer(playerId: playerId, result: result) else { return }
            player.pause()
            result(nil)
            
        case "seekTo":
            guard let player = getPlayer(playerId: playerId, result: result),
                  let position = args?["position"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing position", details: nil))
                return
            }
            player.seekTo(position: position)
            result(nil)
            
        case "setVolume":
            guard let player = getPlayer(playerId: playerId, result: result),
                  let volume = args?["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing volume", details: nil))
                return
            }
            player.setVolume(volume: volume)
            result(nil)
            
        case "setSpeed":
            guard let player = getPlayer(playerId: playerId, result: result),
                  let speed = args?["speed"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing speed", details: nil))
                return
            }
            player.setSpeed(speed: speed)
            result(nil)
            
        case "getDuration":
            guard let player = getPlayer(playerId: playerId, result: result) else { return }
            result(player.getDuration())
            
        case "getCurrentPosition":
            guard let player = getPlayer(playerId: playerId, result: result) else { return }
            result(player.getCurrentPosition())
            
        case "getBufferedPosition":
            guard let player = getPlayer(playerId: playerId, result: result) else { return }
            result(player.getBufferedPosition())
            
        case "getAvailableQualities":
            guard let player = getPlayer(playerId: playerId, result: result) else { return }
            result(player.getAvailableQualities())
            
        case "setQuality":
            guard let player = getPlayer(playerId: playerId, result: result),
                  let index = args?["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing index", details: nil))
                return
            }
            player.setQuality(index: index)
            result(nil)
            
        case "setAutoQuality":
            guard let player = getPlayer(playerId: playerId, result: result) else { return }
            player.setAutoQuality()
            result(nil)
            
        case "getAvailableAudioTracks":
            guard let player = getPlayer(playerId: playerId, result: result) else { return }
            result(player.getAvailableAudioTracks())
            
        case "setAudioTrack":
            guard let player = getPlayer(playerId: playerId, result: result),
                  let index = args?["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing index", details: nil))
                return
            }
            player.setAudioTrack(index: index)
            result(nil)
            
        case "getAvailableSubtitles":
            guard let player = getPlayer(playerId: playerId, result: result) else { return }
            result(player.getAvailableSubtitles())
            
        case "setSubtitle":
            guard let player = getPlayer(playerId: playerId, result: result),
                  let index = args?["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing index", details: nil))
                return
            }
            player.setSubtitle(index: index)
            result(nil)
            
        case "enterPiP":
            result(FlutterError(code: "NOT_IMPLEMENTED", message: "PiP not yet implemented in multi-instance mode", details: nil))
            
        case "getNetworkStatus":
            result([
                "isConnected": true,
                "type": "unknown"
            ])
            
        case "dispose":
            guard let pid = playerId else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
                return
            }
            disposePlayer(playerId: pid, result: result)
            
        // Cache management (iOS uses system-level AVPlayer caching)
        case "getCacheSize":
            // iOS doesn't expose cache size directly
            // AVPlayer uses system URLCache
            let cacheSize = URLCache.shared.currentDiskUsage
            result(Int64(cacheSize))
            
        case "clearCache":
            // Clear URLCache used by AVPlayer
            URLCache.shared.removeAllCachedResponses()
            result(nil)
            
        case "isCacheEnabled":
            // AVPlayer always uses system caching for HLS
            result(true)
            
        // Cast methods - iOS uses native AirPlay via AVRoutePickerView
        // These stubs keep API compatibility with Android
        case "initCast":
            // AirPlay is always available on iOS
            result(true)
            
        case "getCastDevices":
            // AirPlay device selection is handled natively by iOS
            result([])
            
        case "castTo":
            // Use showAirPlayPicker instead
            result(false)
            
        case "castMedia", "castPlay", "castPause", "castSeek", "castStop":
            // Remote control works via MPRemoteCommandCenter on iOS
            result(nil)
            
        case "castDisconnect":
            result(nil)
            
        case "getCastState":
            // Check if external playback is active
            result("notConnected")
            
        case "isCasting":
            result(false)
            
        case "showAirPlayPicker":
            // This would need to present AVRoutePickerView via UIKit
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Private Methods
    
    private static let maxPlayers = 5
    private var playerAccessOrder: [String] = []
    
    private func initialize(playerId: String, url: String, result: @escaping FlutterResult) {
        // Check if player already exists
        if let existing = players[playerId], !existing.isPlayerDisposed() {
            print("[NativeVideoPlayerPlugin] Player \(playerId) exists, disposing and recreating")
            disposePlayerInternal(playerId: playerId)
        }
        
        // Evict oldest player if at capacity
        if players.count >= NativeVideoPlayerPlugin.maxPlayers {
            if let oldestId = playerAccessOrder.first, oldestId != playerId {
                print("[NativeVideoPlayerPlugin] Max players (\(NativeVideoPlayerPlugin.maxPlayers)) reached, evicting: \(oldestId)")
                disposePlayerInternal(playerId: oldestId)
            }
        }
        
        // Create player instance
        let player = VideoPlayerInstance(playerId: playerId, textureRegistry: textureRegistry)
        players[playerId] = player
        
        // Update access order
        playerAccessOrder.removeAll { $0 == playerId }
        playerAccessOrder.append(playerId)
        
        // Create event channel for this player
        let eventChannel = FlutterEventChannel(
            name: "\(NativeVideoPlayerPlugin.eventChannelPrefix)\(playerId)",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(PlayerStreamHandler(player: player))
        eventChannels[playerId] = eventChannel
        
        // Initialize player
        let textureId = player.initialize(url: url)
        
        // Check for initialization failure
        if textureId < 0 {
            result(FlutterError(code: "INIT_FAILED", message: "Failed to initialize player", details: nil))
            disposePlayerInternal(playerId: playerId)
            return
        }
        
        result(["textureId": textureId])
        print("[NativeVideoPlayerPlugin] Initialized player \(playerId) (total: \(players.count))")
    }
    
    private func initializeWithDrm(
        playerId: String,
        url: String,
        licenseUrl: String,
        certificateUrl: String,
        headers: [String: String]?,
        result: @escaping FlutterResult
    ) {
        // Same eviction logic as initialize
        if players.count >= NativeVideoPlayerPlugin.maxPlayers {
            if let oldestId = playerAccessOrder.first, oldestId != playerId {
                print("[NativeVideoPlayerPlugin] Max players reached, evicting: \(oldestId)")
                disposePlayerInternal(playerId: oldestId)
            }
        }
        
        let player = VideoPlayerInstance(playerId: playerId, textureRegistry: textureRegistry)
        players[playerId] = player
        
        playerAccessOrder.removeAll { $0 == playerId }
        playerAccessOrder.append(playerId)
        
        let eventChannel = FlutterEventChannel(
            name: "\(NativeVideoPlayerPlugin.eventChannelPrefix)\(playerId)",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(PlayerStreamHandler(player: player))
        eventChannels[playerId] = eventChannel
        
        // Initialize with DRM
        let textureId = player.initializeWithDrm(
            url: url,
            licenseUrl: licenseUrl,
            certificateUrl: certificateUrl,
            headers: headers
        )
        
        if textureId < 0 {
            result(FlutterError(code: "DRM_INIT_FAILED", message: "Failed to initialize DRM player", details: nil))
            disposePlayerInternal(playerId: playerId)
            return
        }
        
        result(["textureId": textureId])
        print("[NativeVideoPlayerPlugin] Initialized DRM player \(playerId) (total: \(players.count))")
    }
    
    private func preload(playerId: String, url: String, result: @escaping FlutterResult) {
        // Same eviction logic as initialize
        if players.count >= NativeVideoPlayerPlugin.maxPlayers {
            if let oldestId = playerAccessOrder.first, oldestId != playerId {
                print("[NativeVideoPlayerPlugin] Max players reached, evicting: \(oldestId)")
                disposePlayerInternal(playerId: oldestId)
            }
        }
        
        let player = VideoPlayerInstance(playerId: playerId, textureRegistry: textureRegistry)
        players[playerId] = player
        
        playerAccessOrder.removeAll { $0 == playerId }
        playerAccessOrder.append(playerId)
        
        let eventChannel = FlutterEventChannel(
            name: "\(NativeVideoPlayerPlugin.eventChannelPrefix)\(playerId)",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(PlayerStreamHandler(player: player))
        eventChannels[playerId] = eventChannel
        
        let textureId = player.preload(url: url)
        result(["textureId": textureId])
    }
    
    private func getPlayer(playerId: String?, result: @escaping FlutterResult) -> VideoPlayerInstance? {
        guard let pid = playerId else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing playerId", details: nil))
            return nil
        }
        guard let player = players[pid] else {
            result(FlutterError(code: "NO_PLAYER", message: "Player not found: \(pid)", details: nil))
            return nil
        }
        
        // Update access order (LRU)
        playerAccessOrder.removeAll { $0 == pid }
        playerAccessOrder.append(pid)
        
        return player
    }
    
    private func disposePlayer(playerId: String, result: @escaping FlutterResult) {
        disposePlayerInternal(playerId: playerId)
        result(nil)
    }
    
    /// Internal dispose for LRU eviction without result callback
    private func disposePlayerInternal(playerId: String) {
        let player = players.removeValue(forKey: playerId)
        player?.dispose()
        
        eventChannels.removeValue(forKey: playerId)
        playerAccessOrder.removeAll { $0 == playerId }
        
        print("[NativeVideoPlayerPlugin] Disposed player \(playerId) (remaining: \(players.count))")
    }
}

// MARK: - Stream Handler

class PlayerStreamHandler: NSObject, FlutterStreamHandler {
    private weak var player: VideoPlayerInstance?
    
    init(player: VideoPlayerInstance) {
        self.player = player
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        player?.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        player?.eventSink = nil
        return nil
    }
}

// MARK: - FlutterVideoTexture

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
