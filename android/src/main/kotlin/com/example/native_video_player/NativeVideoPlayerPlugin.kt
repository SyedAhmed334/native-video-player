package com.example.native_video_player

import android.app.Activity
import android.content.Context
import androidx.annotation.NonNull
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * NativeVideoPlayerPlugin - Multi-instance video player plugin
 * Routes method calls to the correct VideoPlayerInstance based on playerId
 */
@UnstableApi
class NativeVideoPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    companion object {
        private const val METHOD_CHANNEL = "native_video_player/method"
        private const val EVENT_CHANNEL_PREFIX = "native_video_player/event/"
        private const val TAG = "NativeVideoPlayerPlugin"
        
        // Maximum concurrent players to prevent memory exhaustion
        private const val MAX_PLAYERS = 5
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var context: Context
    private lateinit var textureRegistry: TextureRegistry
    private var activity: Activity? = null

    // Multi-instance player storage
    private val players = mutableMapOf<String, VideoPlayerInstance>()
    private val eventChannels = mutableMapOf<String, EventChannel>()
    
    // Track player access order for LRU eviction
    private val playerAccessOrder = mutableListOf<String>()
    
    // Cast manager for Chromecast
    private var castManager: CastManager? = null
    
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        // Initialize video cache
        VideoCacheManager.initialize(context)

        android.util.Log.d(TAG, "Plugin attached to engine")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        
        // Dispose all players
        players.values.forEach { it.dispose() }
        players.clear()
        eventChannels.clear()

        // Release cache
        VideoCacheManager.release()

        android.util.Log.d(TAG, "Plugin detached from engine")
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        players.values.forEach { it.setActivity(activity) }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        players.values.forEach { it.setActivity(activity) }
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        val playerId = call.argument<String>("playerId")
        
        try {
            when (call.method) {
                "initialize" -> {
                    if (playerId == null) {
                        result.error("INVALID_ARGS", "Missing playerId", null)
                        return
                    }
                    val url = call.argument<String>("url")!!
                    val drm = call.argument<Map<String, Any>>("drm")
                    
                    if (drm != null) {
                        // DRM initialization
                        val drmType = drm["type"] as? String ?: "widevine"
                        val licenseUrl = drm["licenseUrl"] as? String ?: ""
                        @Suppress("UNCHECKED_CAST")
                        val headers = drm["headers"] as? Map<String, String>
                        initializeWithDrm(playerId, url, drmType, licenseUrl, headers, result)
                    } else {
                        initialize(playerId, url, result)
                    }
                }
                "preload" -> {
                    if (playerId == null) {
                        result.error("INVALID_ARGS", "Missing playerId", null)
                        return
                    }
                    val url = call.argument<String>("url")!!
                    preload(playerId, url, result)
                }
                "play" -> {
                    getPlayer(playerId, result)?.let {
                        it.play()
                        result.success(null)
                    }
                }
                "pause" -> {
                    getPlayer(playerId, result)?.let {
                        it.pause()
                        result.success(null)
                    }
                }
                "seekTo" -> {
                    getPlayer(playerId, result)?.let {
                        val position = call.argument<Number>("position")!!.toLong()
                        it.seekTo(position)
                        result.success(null)
                    }
                }
                "setVolume" -> {
                    getPlayer(playerId, result)?.let {
                        val volume = call.argument<Double>("volume")!!
                        it.setVolume(volume)
                        result.success(null)
                    }
                }
                "setSpeed" -> {
                    getPlayer(playerId, result)?.let {
                        val speed = call.argument<Double>("speed")!!
                        it.setSpeed(speed)
                        result.success(null)
                    }
                }
                "getDuration" -> {
                    getPlayer(playerId, result)?.let {
                        result.success(it.getDuration())
                    }
                }
                "getCurrentPosition" -> {
                    getPlayer(playerId, result)?.let {
                        result.success(it.getCurrentPosition())
                    }
                }
                "getBufferedPosition" -> {
                    getPlayer(playerId, result)?.let {
                        result.success(it.getBufferedPosition())
                    }
                }
                "getAvailableQualities" -> {
                    getPlayer(playerId, result)?.let {
                        result.success(it.getAvailableQualities())
                    }
                }
                "setQuality" -> {
                    getPlayer(playerId, result)?.let {
                        val index = call.argument<Int>("index")!!
                        it.setQuality(index)
                        result.success(null)
                    }
                }
                "setAutoQuality" -> {
                    getPlayer(playerId, result)?.let {
                        it.setAutoQuality()
                        result.success(null)
                    }
                }
                "getAvailableAudioTracks" -> {
                    getPlayer(playerId, result)?.let {
                        result.success(it.getAvailableAudioTracks())
                    }
                }
                "setAudioTrack" -> {
                    getPlayer(playerId, result)?.let {
                        val index = call.argument<Int>("index")!!
                        it.setAudioTrack(index)
                        result.success(null)
                    }
                }
                "getAvailableSubtitles" -> {
                    getPlayer(playerId, result)?.let {
                        result.success(it.getAvailableSubtitles())
                    }
                }
                "setSubtitle" -> {
                    getPlayer(playerId, result)?.let {
                        val index = call.argument<Int>("index")!!
                        it.setSubtitle(index)
                        result.success(null)
                    }
                }
                "enterPiP" -> {
                    // PiP needs special handling
                    result.error("NOT_IMPLEMENTED", "PiP not yet implemented in multi-instance mode", null)
                }
                "getNetworkStatus" -> {
                    // Network status is global
                    result.success(mapOf(
                        "isConnected" to true,
                        "type" to "unknown"
                    ))
                }
                "dispose" -> {
                    if (playerId != null) {
                        disposePlayer(playerId, result)
                    } else {
                        result.error("INVALID_ARGS", "Missing playerId", null)
                    }
                }
                // Cache management
                "getCacheSize" -> {
                    result.success(VideoCacheManager.getCacheSize())
                }
                "clearCache" -> {
                    VideoCacheManager.clearCache()
                    result.success(null)
                }
                "isCacheEnabled" -> {
                    result.success(VideoCacheManager.isAvailable())
                }
                // Cast methods
                "initCast" -> {
                    initCast(result)
                }
                "getCastDevices" -> {
                    val devices = castManager?.getDevices() ?: emptyList()
                    result.success(devices)
                }
                "castTo" -> {
                    val deviceId = call.argument<String>("deviceId")
                    if (deviceId != null) {
                        val success = castManager?.connect(deviceId) ?: false
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGS", "Missing deviceId", null)
                    }
                }
                "castMedia" -> {
                    val url = call.argument<String>("url")!!
                    val title = call.argument<String>("title")
                    val position = call.argument<Long>("position") ?: 0L
                    val success = castManager?.loadMedia(url, title, startPosition = position) ?: false
                    result.success(success)
                }
                "castPlay" -> {
                    castManager?.play()
                    result.success(null)
                }
                "castPause" -> {
                    castManager?.pause()
                    result.success(null)
                }
                "castSeek" -> {
                    val position = call.argument<Long>("position") ?: 0L
                    castManager?.seek(position)
                    result.success(null)
                }
                "castStop" -> {
                    castManager?.stop()
                    result.success(null)
                }
                "castDisconnect" -> {
                    castManager?.disconnect()
                    result.success(null)
                }
                "getCastState" -> {
                    result.success(castManager?.getCastState() ?: "notInitialized")
                }
                "isCasting" -> {
                    result.success(castManager?.isCasting() ?: false)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun initialize(playerId: String, url: String, result: MethodChannel.Result) {
        // Check if player already exists - reuse it
        val existingPlayer = players[playerId]
        if (existingPlayer != null && !existingPlayer.isDisposed()) {
            android.util.Log.d(TAG, "Player $playerId already exists, disposing and recreating")
            disposePlayerInternal(playerId)
        }
        
        // Evict oldest player if at capacity
        if (players.size >= MAX_PLAYERS) {
            val oldestPlayerId = playerAccessOrder.firstOrNull()
            if (oldestPlayerId != null && oldestPlayerId != playerId) {
                android.util.Log.w(TAG, "Max players ($MAX_PLAYERS) reached, evicting oldest: $oldestPlayerId")
                disposePlayerInternal(oldestPlayerId)
            }
        }
        
        try {
            // Create player instance
            val player = VideoPlayerInstance(context, textureRegistry, playerId)
            player.setActivity(activity)
            players[playerId] = player
            
            // Update access order
            playerAccessOrder.remove(playerId)
            playerAccessOrder.add(playerId)

            // Create event channel for this player
            val eventChannel = EventChannel(
                flutterPluginBinding.binaryMessenger,
                "$EVENT_CHANNEL_PREFIX$playerId"
            )
            eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    player.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    player.eventSink = null
                }
            })
            eventChannels[playerId] = eventChannel

            // Initialize player
            val textureId = player.initialize(url)
            
            // Check for initialization failure
            if (textureId < 0) {
                result.error("INIT_FAILED", "Failed to initialize player", null)
                disposePlayerInternal(playerId)
                return
            }
            
            result.success(mapOf("textureId" to textureId))
            android.util.Log.d(TAG, "Initialized player $playerId (total: ${players.size})")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error initializing player $playerId: ${e.message}", e)
            result.error("ERROR", "Initialization error: ${e.message}", null)
            disposePlayerInternal(playerId)
        }
    }

    private fun initializeWithDrm(
        playerId: String,
        url: String,
        drmType: String,
        licenseUrl: String,
        headers: Map<String, String>?,
        result: MethodChannel.Result
    ) {
        // Same eviction/initialization pattern as initialize()
        if (players.size >= MAX_PLAYERS) {
            val oldest = playerAccessOrder.firstOrNull()
            if (oldest != null && oldest != playerId) {
                android.util.Log.d(TAG, "Evicting player $oldest to make room for $playerId")
                disposePlayerInternal(oldest)
            }
        }

        try {
            val player = VideoPlayerInstance(context, textureRegistry, playerId)
            player.setActivity(activity)
            players[playerId] = player

            // Track access order
            playerAccessOrder.remove(playerId)
            playerAccessOrder.add(playerId)

            // Set up event channel
            val eventChannel = EventChannel(
                flutterPluginBinding.binaryMessenger,
                "$EVENT_CHANNEL_PREFIX$playerId"
            )
            eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    player.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    player.eventSink = null
                }
            })
            eventChannels[playerId] = eventChannel

            // Initialize with DRM
            val textureId = player.initializeWithDrm(url, drmType, licenseUrl, headers)

            if (textureId < 0) {
                result.error("DRM_INIT_FAILED", "Failed to initialize DRM player", null)
                disposePlayerInternal(playerId)
                return
            }

            result.success(mapOf("textureId" to textureId))
            android.util.Log.d(TAG, "Initialized DRM player $playerId with $drmType (total: ${players.size})")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error initializing DRM player $playerId: ${e.message}", e)
            result.error("DRM_ERROR", "DRM initialization error: ${e.message}", null)
            disposePlayerInternal(playerId)
        }
    }
    private fun preload(playerId: String, url: String, result: MethodChannel.Result) {
        val player = VideoPlayerInstance(context, textureRegistry, playerId)
        player.setActivity(activity)
        players[playerId] = player

        val eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "$EVENT_CHANNEL_PREFIX$playerId"
        )
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                player.eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                player.eventSink = null
            }
        })
        eventChannels[playerId] = eventChannel

        val textureId = player.preload(url)
        result.success(mapOf("textureId" to textureId))
    }

    private fun getPlayer(playerId: String?, result: MethodChannel.Result): VideoPlayerInstance? {
        if (playerId == null) {
            result.error("INVALID_ARGS", "Missing playerId", null)
            return null
        }
        val player = players[playerId]
        if (player == null) {
            result.error("NO_PLAYER", "Player not found: $playerId", null)
            return null
        }
        return player
    }

    private fun disposePlayer(playerId: String, result: MethodChannel.Result) {
        disposePlayerInternal(playerId)
        result.success(null)
    }
    
    /**
     * Internal dispose without MethodChannel.Result - for LRU eviction
     */
    private fun disposePlayerInternal(playerId: String) {
        try {
            val player = players.remove(playerId)
            player?.dispose()
            
            eventChannels.remove(playerId)
            playerAccessOrder.remove(playerId)
            
            android.util.Log.d(TAG, "Disposed player $playerId (remaining: ${players.size})")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error disposing player $playerId: ${e.message}", e)
        }
    }
    
    /**
     * Initialize Cast SDK
     */
    private fun initCast(result: MethodChannel.Result) {
        try {
            if (castManager == null) {
                castManager = CastManager(context, activity)
            }
            val success = castManager?.initialize() ?: false
            result.success(success)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to initialize Cast: ${e.message}")
            result.error("CAST_ERROR", "Failed to initialize Cast: ${e.message}", null)
        }
    }
}
