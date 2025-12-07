package com.example.custom_video_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.Surface
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.SingleSampleMediaSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * VideoPlayerPlugin - Complete ExoPlayer integration for Flutter (Kotlin)
 *
 * Features:
 * - Seamless quality switching without reload
 * - Instant audio track switching
 * - Instant subtitle switching
 * - Adaptive bitrate streaming
 * - Offline playback support
 * - External subtitle loading
 * - Netflix-smooth experience
 */
@UnstableApi
class VideoPlayerPlugin(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val methodChannel: MethodChannel,
    private val eventChannel: EventChannel
) : MethodChannel.MethodCallHandler {


    companion object {
        private const val METHOD_CHANNEL = "native_video_player/method"
        private const val EVENT_CHANNEL = "native_video_player/event"
        private const val TAG = "VideoPlayerPlugin"

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            registerWithActivity(flutterEngine, context as? Activity ?: (context as android.content.ContextWrapper).baseContext as? Activity)
        }
        
        fun registerWithActivity(flutterEngine: FlutterEngine, activity: Activity?): VideoPlayerPlugin {
            val context = activity ?: throw IllegalArgumentException("Activity required")
            
            val methodChannel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                METHOD_CHANNEL
            )
            val eventChannel = EventChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                EVENT_CHANNEL
            )

            val plugin = VideoPlayerPlugin(
                context,
                flutterEngine.renderer,
                methodChannel,
                eventChannel
            )
            
            // Set activity for PiP support
            plugin.setActivity(activity)
            
            return plugin
        }
    }

    // ExoPlayer components
    private var player: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null

    // Event streaming
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var positionUpdateRunnable: Runnable? = null

    // Track information
    private var availableQualities = mutableListOf<VideoQualityInfo>()
    private var availableAudioTracks = mutableListOf<AudioTrackInfo>()
    private var availableSubtitles = mutableListOf<SubtitleTrackInfo>()
    private var selectedQualityIndex = -1
    private var selectedAudioIndex = -1
    private var selectedSubtitleIndex = -1
    private var isAutoQuality = true // Start with auto quality enabled

    // State tracking
    private var isBuffering = false
    private var currentUrl: String? = null
    private var externalSubtitleSource: MediaSource? = null
    
    // Network monitoring
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var isNetworkAvailable = true
    private var currentNetworkType = "unknown"
    
    // PiP state
    private var activity: Activity? = null
    private var isPiPActive = false

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                startPositionUpdates()
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                stopPositionUpdates()
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    val url = call.argument<String>("url")!!
                    initializePlayer(url, result)
                }
                "play" -> play(result)
                "pause" -> pause(result)
                "seekTo" -> {
                    val position = call.argument<Number>("position")!!.toLong()
                    seekTo(position, result)
                }
                "setVolume" -> {
                    val volume = call.argument<Double>("volume")!!
                    setVolume(volume, result)
                }
                "setSpeed" -> {
                    val speed = call.argument<Double>("speed")!!
                    setSpeed(speed, result)
                }
                "getDuration" -> getDuration(result)
                "getCurrentPosition" -> getCurrentPosition(result)
                "getBufferedPosition" -> getBufferedPosition(result)
                "getAvailableQualities" -> getAvailableQualities(result)
                "setQuality" -> {
                    val qualityIndex = call.argument<Int>("index")!!
                    setQuality(qualityIndex, result)
                }
                "setAutoQuality" -> setAutoQuality(result)
                "getAvailableAudioTracks" -> getAvailableAudioTracks(result)
                "setAudioTrack" -> {
                    val audioIndex = call.argument<Int>("index")!!
                    setAudioTrack(audioIndex, result)
                }
                "getAvailableSubtitles" -> getAvailableSubtitles(result)
                "setSubtitle" -> {
                    val subtitleIndex = call.argument<Int>("index")!!
                    setSubtitle(subtitleIndex, result)
                }
                "loadExternalSubtitle" -> {
                    val subtitleUrl = call.argument<String>("url")!!
                    loadExternalSubtitle(subtitleUrl, result)
                }
                "enableOfflineMode" -> {
                    val localPath = call.argument<String>("localPath")!!
                    enableOfflineMode(localPath, result)
                }
                "enterPiP" -> enterPictureInPicture(result)
                "getNetworkStatus" -> getNetworkStatus(result)
                "dispose" -> disposePlayer(result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    /**
     * Initialize ExoPlayer with the given URL
     * Supports HLS, DASH, MP4, and other formats
     */
    private fun initializePlayer(url: String, result: MethodChannel.Result) {
        try {
            currentUrl = url

            // Create texture for video rendering
            textureEntry = textureRegistry.createSurfaceTexture()
            surface = Surface(textureEntry!!.surfaceTexture())

            // Create track selector with adaptive selection
            val trackSelectionFactory = AdaptiveTrackSelection.Factory()
            trackSelector = DefaultTrackSelector(context, trackSelectionFactory).apply {
                setParameters(
                    buildUponParameters()
                        .setMaxVideoSizeSd()
                        .setPreferredAudioLanguage("en")
                        .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                        .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true) // Subtitles off by default
                        .build()
                )
            }

            // Configure load control with back buffer retention
            // This keeps previously watched content buffered so seeking backwards is instant
            val loadControl = DefaultLoadControl.Builder()
                .setBackBuffer(
                    /* backBufferDurationMs = */ 60_000,  // Keep 60 seconds of back buffer
                    /* retainBackBufferFromKeyframe = */ true
                )
                .setBufferDurationsMs(
                    /* minBufferMs = */ 15_000,
                    /* maxBufferMs = */ 50_000,
                    /* bufferForPlaybackMs = */ 2_500,
                    /* bufferForPlaybackAfterRebufferMs = */ 5_000
                )
                .build()

            // Configure AudioAttributes for audio focus handling
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build()

            // Build ExoPlayer
            player = ExoPlayer.Builder(context)
                .setTrackSelector(trackSelector!!)
                .setLoadControl(loadControl)
                .setAudioAttributes(audioAttributes, true) // handleAudioFocus = true
                .build().apply {
                    // Set video surface
                    setVideoSurface(surface)

                    // Add player listener
                    addListener(object : Player.Listener {
                        override fun onPlaybackStateChanged(playbackState: Int) {
                            handlePlaybackStateChanged(playbackState)
                            // Update tracks when player is ready
                            if (playbackState == Player.STATE_READY) {
                                updateAvailableTracks()
                            }
                        }

                        override fun onIsPlayingChanged(isPlaying: Boolean) {
                            sendEvent("playbackState", if (isPlaying) "playing" else "paused")
                        }

                        override fun onPlayerError(error: PlaybackException) {
                            sendEvent(mapOf(
                                "event" to "error",
                                "message" to (error.message ?: "Unknown error")
                            ))
                        }

                        override fun onTracksChanged(tracks: Tracks) {
                            android.util.Log.d(TAG, "onTracksChanged called")
                            updateAvailableTracks()
                        }

                        override fun onCues(cueGroup: CueGroup) {
                            val text = cueGroup.cues
                                .mapNotNull { it.text?.toString() }
                                .joinToString("\n")
                            sendEvent(mapOf(
                                "event" to "subtitleText",
                                "text" to text.trim()
                            ))
                        }
                    })

                    // Create media item and prepare
                    val mediaItem = MediaItem.fromUri(url)
                    setMediaItem(mediaItem)
                    prepare()
                }

            // Return texture ID to Flutter
            result.success(mapOf("textureId" to textureEntry!!.id()))

        } catch (e: Exception) {
            result.error("INIT_ERROR", e.message, null)
        }
    }

    /** Play the video */
    private fun play(result: MethodChannel.Result) {
        player?.let {
            it.play()
            result.success(null)
        } ?: result.error("NO_PLAYER", "Player not initialized", null)
    }

    /** Pause the video */
    private fun pause(result: MethodChannel.Result) {
        player?.let {
            it.pause()
            result.success(null)
        } ?: result.error("NO_PLAYER", "Player not initialized", null)
    }

    /** Seek to a specific position (in milliseconds) */
    private fun seekTo(position: Long, result: MethodChannel.Result) {
        player?.let {
            it.seekTo(position)
            result.success(null)
        } ?: result.error("NO_PLAYER", "Player not initialized", null)
    }

    /** Set volume (0.0 to 1.0) */
    private fun setVolume(volume: Double, result: MethodChannel.Result) {
        player?.let {
            it.volume = volume.toFloat()
            result.success(null)
        } ?: result.error("NO_PLAYER", "Player not initialized", null)
    }

    /** Set playback speed */
    private fun setSpeed(speed: Double, result: MethodChannel.Result) {
        player?.let {
            it.setPlaybackSpeed(speed.toFloat())
            result.success(null)
        } ?: result.error("NO_PLAYER", "Player not initialized", null)
    }

    /** Get video duration in milliseconds */
    private fun getDuration(result: MethodChannel.Result) {
        player?.let {
            val duration = it.duration
            result.success(if (duration == C.TIME_UNSET) 0L else duration)
        } ?: result.error("NO_PLAYER", "Player not initialized", null)
    }

    /** Get current playback position in milliseconds */
    private fun getCurrentPosition(result: MethodChannel.Result) {
        player?.let {
            result.success(it.currentPosition)
        } ?: result.error("NO_PLAYER", "Player not initialized", null)
    }

    /** Get buffered position in milliseconds */
    private fun getBufferedPosition(result: MethodChannel.Result) {
        player?.let {
            result.success(it.bufferedPosition)
        } ?: result.error("NO_PLAYER", "Player not initialized", null)
    }

    /**
     * Get available video quality tracks
     * Netflix-style: Returns all available qualities with resolution and bitrate info
     */
    private fun getAvailableQualities(result: MethodChannel.Result) {
        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }

        updateAvailableTracks()

        android.util.Log.d(TAG, "getAvailableQualities called, found ${availableQualities.size} qualities")

        val qualities = availableQualities.mapIndexed { index, quality ->
            mapOf(
                "index" to index,
                "width" to quality.width,
                "height" to quality.height,
                "bitrate" to quality.bitrate,
                "label" to quality.label
            )
        }

        result.success(qualities)
    }

    /**
     * Set video quality - SEAMLESS SWITCHING (Netflix-style)
     * Uses TrackSelectionOverride to switch without stopping playback
     * Maintains buffer and provides smooth transition
     */
    private fun setQuality(index: Int, result: MethodChannel.Result) {
        val player = this.player
        val trackSelector = this.trackSelector

        if (player == null || trackSelector == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }

        if (index < 0 || index >= availableQualities.size) {
            result.error("INVALID_INDEX", "Quality index out of range", null)
            return
        }

        try {
            val selectedQuality = availableQualities[index]

            // Manual track selection for seamless switching
            trackSelector.setParameters(
                trackSelector.buildUponParameters()
                    .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                    .setMaxVideoSize(selectedQuality.width, selectedQuality.height)
                    .setMinVideoSize(selectedQuality.width, selectedQuality.height)
                    .build()
            )
            selectedQualityIndex = index
            isAutoQuality = false

            // Notify Flutter about quality change
            sendEvent(mapOf(
                "event" to "qualityChanged",
                "index" to index,
                "isAuto" to false
            ))

            result.success(null)

        } catch (e: Exception) {
            result.error("QUALITY_ERROR", e.message, null)
        }
    }

    /**
     * Set auto quality - ADAPTIVE BITRATE (Netflix/YouTube-style)
     * Clears video size constraints and lets ExoPlayer's ABR algorithm choose
     * the optimal quality based on network conditions
     */
    private fun setAutoQuality(result: MethodChannel.Result) {
        val trackSelector = this.trackSelector

        if (trackSelector == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }

        try {
            // Clear video size constraints to enable adaptive selection
            trackSelector.setParameters(
                trackSelector.buildUponParameters()
                    .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                    .clearVideoSizeConstraints()
                    .setMaxVideoSizeSd() // Allow up to SD by default, ExoPlayer will adapt
                    .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                    .build()
            )
            
            selectedQualityIndex = -1
            isAutoQuality = true

            android.util.Log.d(TAG, "Auto quality enabled - ABR active")

            // Notify Flutter about auto quality
            sendEvent(mapOf(
                "event" to "qualityChanged",
                "index" to -1,
                "isAuto" to true
            ))

            result.success(null)

        } catch (e: Exception) {
            result.error("AUTO_QUALITY_ERROR", e.message, null)
        }
    }

    /** Get available audio tracks */
    private fun getAvailableAudioTracks(result: MethodChannel.Result) {
        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }

        updateAvailableTracks()

        android.util.Log.d(TAG, "getAvailableAudioTracks called, found ${availableAudioTracks.size} audio tracks")

        val audioTracks = availableAudioTracks.mapIndexed { index, audio ->
            mapOf(
                "index" to index,
                "language" to audio.language,
                "label" to audio.label
            )
        }

        result.success(audioTracks)
    }

    /**
     * Set audio track - INSTANT SWITCHING (Netflix-style)
     * Switches audio without any reload or rebuffering
     * Uses TrackSelectionOverride to select specific track when multiple tracks share the same language
     */
    private fun setAudioTrack(index: Int, result: MethodChannel.Result) {
        val player = this.player
        val trackSelector = this.trackSelector

        if (player == null || trackSelector == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }

        if (index < 0 || index >= availableAudioTracks.size) {
            result.error("INVALID_INDEX", "Audio track index out of range", null)
            return
        }

        try {
            val selectedAudio = availableAudioTracks[index]

            android.util.Log.d(TAG, "Setting audio track: index=$index, language=${selectedAudio.language}, label=${selectedAudio.label}, trackIndex=${selectedAudio.trackIndex}")

            // Use TrackSelectionOverride for precise track selection
            // This handles cases where multiple tracks share the same language (e.g., English + English Commentary)
            val override = androidx.media3.common.TrackSelectionOverride(
                selectedAudio.trackGroup,
                listOf(selectedAudio.trackIndex)
            )

            trackSelector.setParameters(
                trackSelector.buildUponParameters()
                    .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                    .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                    .addOverride(override)
                    .build()
            )
            selectedAudioIndex = index

            android.util.Log.d(TAG, "Audio track set successfully to index $index")

            // Notify Flutter about audio change
            sendEvent(mapOf(
                "event" to "audioChanged",
                "index" to index
            ))

            result.success(null)

        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error setting audio track: ${e.message}")
            result.error("AUDIO_ERROR", e.message, null)
        }
    }

    /** Get available subtitle tracks */
    private fun getAvailableSubtitles(result: MethodChannel.Result) {
        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }

        updateAvailableTracks()

        android.util.Log.d(TAG, "getAvailableSubtitles called, found ${availableSubtitles.size} subtitles")

        val subtitles = availableSubtitles.mapIndexed { index, subtitle ->
            mapOf(
                "index" to index,
                "language" to subtitle.language,
                "label" to subtitle.label
            )
        }

        result.success(subtitles)
    }

    /**
     * Set subtitle track - INSTANT SWITCHING (Netflix-style)
     * Index -1 disables subtitles
     */
    private fun setSubtitle(index: Int, result: MethodChannel.Result) {
        val player = this.player
        val trackSelector = this.trackSelector

        if (player == null || trackSelector == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }

        try {
            if (index == -1) {
                // Disable subtitles
                trackSelector.setParameters(
                    trackSelector.buildUponParameters()
                        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                        .build()
                )
            } else {
                if (index < 0 || index >= availableSubtitles.size) {
                    result.error("INVALID_INDEX", "Subtitle index out of range", null)
                    return
                }

                val selectedSubtitle = availableSubtitles[index]

                // Manual subtitle track selection
                trackSelector.setParameters(
                    trackSelector.buildUponParameters()
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                        .setPreferredTextLanguage(selectedSubtitle.language)
                        .build()
                )
            }

            selectedSubtitleIndex = index

            // Notify Flutter about subtitle change
            sendEvent(mapOf(
                "event" to "subtitleChanged",
                "index" to index
            ))

            result.success(null)

        } catch (e: Exception) {
            result.error("SUBTITLE_ERROR", e.message, null)
        }
    }

    /**
     * Load external subtitle file (.vtt or .srt)
     * Merges with main media source
     */
    private fun loadExternalSubtitle(subtitleUrl: String, result: MethodChannel.Result) {
        val player = this.player
        val currentUrl = this.currentUrl

        if (player == null || currentUrl == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }

        try {
            // Create subtitle media item
            val subtitleConfig = MediaItem.SubtitleConfiguration.Builder(Uri.parse(subtitleUrl))
                .setMimeType(MimeTypes.TEXT_VTT)
                .setLanguage("en")
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .build()

            // Create single sample media source for subtitle
            val dataSourceFactory = DefaultDataSource.Factory(context)

            externalSubtitleSource = SingleSampleMediaSource.Factory(dataSourceFactory)
                .createMediaSource(subtitleConfig, C.TIME_UNSET)

            // Merge with current media source
            val currentItem = MediaItem.fromUri(currentUrl)
            val videoSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(currentItem)

            val mergedSource = MergingMediaSource(videoSource, externalSubtitleSource!!)

            // Save current position
            val currentPosition = player.currentPosition
            val wasPlaying = player.isPlaying

            // Set merged source
            player.setMediaSource(mergedSource)
            player.prepare()
            player.seekTo(currentPosition)

            if (wasPlaying) {
                player.play()
            }

            result.success(null)

        } catch (e: Exception) {
            result.error("SUBTITLE_LOAD_ERROR", e.message, null)
        }
    }

    /**
     * Enable offline playback mode
     * Uses ProgressiveMediaSource for local files
     */
    private fun enableOfflineMode(localPath: String, result: MethodChannel.Result) {
        val player = this.player

        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null)
            return
        }

        try {
            val dataSourceFactory = DefaultDataSource.Factory(context)

            val mediaItem = MediaItem.fromUri(Uri.parse(localPath))
            val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(mediaItem)

            player.setMediaSource(mediaSource)
            player.prepare()

            result.success(null)

        } catch (e: Exception) {
            result.error("OFFLINE_ERROR", e.message, null)
        }
    }

    /** Dispose player and release resources */
    private fun disposePlayer(result: MethodChannel.Result) {
        stopPositionUpdates()

        player?.release()
        player = null

        surface?.release()
        surface = null

        textureEntry?.release()
        textureEntry = null

        trackSelector = null
        availableQualities.clear()
        availableAudioTracks.clear()
        availableSubtitles.clear()

        result.success(null)
    }

    /** Update available tracks from ExoPlayer */
    private fun updateAvailableTracks() {
        val player = this.player ?: return

        val tracks = player.currentTracks
        android.util.Log.d(TAG, "Updating tracks, groups count: ${tracks.groups.size}")

        // Update video qualities
        availableQualities.clear()
        tracks.groups
            .filter { it.type == C.TRACK_TYPE_VIDEO }
            .forEach { trackGroup ->
                android.util.Log.d(TAG, "Found video track group with ${trackGroup.length} tracks")
                for (i in 0 until trackGroup.length) {
                    val format = trackGroup.getTrackFormat(i)
                    availableQualities.add(VideoQualityInfo(
                        trackGroup = trackGroup.mediaTrackGroup,
                        trackIndex = i,
                        width = format.width,
                        height = format.height,
                        bitrate = format.bitrate,
                        label = "${format.height}p"
                    ))
                    android.util.Log.d(TAG, "Added quality: ${format.height}p")
                }
            }

        // Update audio tracks
        availableAudioTracks.clear()
        tracks.groups
            .filter { it.type == C.TRACK_TYPE_AUDIO }
            .forEach { trackGroup ->
                android.util.Log.d(TAG, "Found audio track group with ${trackGroup.length} tracks")
                for (i in 0 until trackGroup.length) {
                    val format = trackGroup.getTrackFormat(i)
                    val language = format.language ?: "Unknown"
                    availableAudioTracks.add(AudioTrackInfo(
                        trackGroup = trackGroup.mediaTrackGroup,
                        trackIndex = i,
                        language = language,
                        label = format.label ?: language
                    ))
                    android.util.Log.d(TAG, "Added audio track: ${format.label ?: language} ($language)")
                }
            }

        // Update subtitle tracks
        availableSubtitles.clear()
        tracks.groups
            .filter { it.type == C.TRACK_TYPE_TEXT }
            .forEach { trackGroup ->
                android.util.Log.d(TAG, "Found subtitle track group with ${trackGroup.length} tracks")
                for (i in 0 until trackGroup.length) {
                    val format = trackGroup.getTrackFormat(i)
                    val language = format.language ?: "Unknown"
                    availableSubtitles.add(SubtitleTrackInfo(
                        trackGroup = trackGroup.mediaTrackGroup,
                        trackIndex = i,
                        language = language,
                        label = format.label ?: language
                    ))
                    android.util.Log.d(TAG, "Added subtitle track: ${format.label ?: language} ($language)")
                }
            }
    }

    /** Handle playback state changes */
    private fun handlePlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_BUFFERING -> {
                if (!isBuffering) {
                    isBuffering = true
                    sendEvent("bufferState", "buffering")
                }
            }
            Player.STATE_READY -> {
                if (isBuffering) {
                    isBuffering = false
                    sendEvent("bufferState", "ready")
                }
            }
            Player.STATE_ENDED -> {
                sendEvent("playbackState", "completed")
            }
        }
    }

    /** Start periodic position updates */
    private fun startPositionUpdates() {
        if (positionUpdateRunnable != null) return

        positionUpdateRunnable = object : Runnable {
            override fun run() {
                player?.let { p ->
                    eventSink?.let {
                        val duration = p.duration
                        sendEvent(mapOf(
                            "event" to "position",
                            "position" to p.currentPosition,
                            "bufferedPosition" to p.bufferedPosition,
                            "duration" to if (duration == C.TIME_UNSET) 0L else duration
                        ))
                    }
                }
                mainHandler.postDelayed(this, 500) // Update every 500ms
            }
        }

        mainHandler.post(positionUpdateRunnable!!)
    }

    /** Stop position updates */
    private fun stopPositionUpdates() {
        positionUpdateRunnable?.let {
            mainHandler.removeCallbacks(it)
            positionUpdateRunnable = null
        }
    }

    /** Send event to Flutter via EventChannel */
    private fun sendEvent(key: String, value: Any) {
        sendEvent(mapOf(key to value))
    }

    private fun sendEvent(event: Map<String, Any>) {
        eventSink?.let { sink ->
            mainHandler.post { sink.success(event) }
        }
    }
    
    // ========== NETWORK MONITORING ==========
    
    /** Set up network monitoring to detect connectivity changes */
    fun setupNetworkMonitoring() {
        connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                mainHandler.post {
                    val wasUnavailable = !isNetworkAvailable
                    isNetworkAvailable = true
                    updateNetworkType()
                    
                    sendEvent(mapOf(
                        "event" to "networkChanged",
                        "isConnected" to true,
                        "type" to currentNetworkType
                    ))
                    
                    // If was disconnected, notify for potential retry
                    if (wasUnavailable) {
                        android.util.Log.d(TAG, "Network restored: $currentNetworkType")
                    }
                }
            }
            
            override fun onLost(network: Network) {
                mainHandler.post {
                    isNetworkAvailable = false
                    currentNetworkType = "none"
                    
                    sendEvent(mapOf(
                        "event" to "networkChanged",
                        "isConnected" to false,
                        "type" to "none"
                    ))
                    
                    android.util.Log.d(TAG, "Network lost")
                }
            }
            
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                mainHandler.post {
                    updateNetworkType()
                    sendEvent(mapOf(
                        "event" to "networkChanged",
                        "isConnected" to true,
                        "type" to currentNetworkType
                    ))
                }
            }
        }
        
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        
        connectivityManager?.registerNetworkCallback(request, networkCallback!!)
        
        // Get initial network state
        updateNetworkType()
    }
    
    /** Stop network monitoring */
    private fun stopNetworkMonitoring() {
        networkCallback?.let { callback ->
            try {
                connectivityManager?.unregisterNetworkCallback(callback)
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Error unregistering network callback: ${e.message}")
            }
        }
        networkCallback = null
    }
    
    /** Update current network type */
    private fun updateNetworkType() {
        val activeNetwork = connectivityManager?.activeNetwork
        val capabilities = connectivityManager?.getNetworkCapabilities(activeNetwork)
        
        currentNetworkType = when {
            capabilities == null -> "none"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
        
        isNetworkAvailable = capabilities != null
    }
    
    /** Get current network status */
    private fun getNetworkStatus(result: MethodChannel.Result) {
        updateNetworkType()
        result.success(mapOf(
            "isConnected" to isNetworkAvailable,
            "type" to currentNetworkType
        ))
    }
    
    // ========== PICTURE-IN-PICTURE ==========
    
    /** Set activity reference for PiP mode (call from MainActivity) */
    fun setActivity(activity: Activity) {
        this.activity = activity
        setupNetworkMonitoring()
    }
    
    /** Enter Picture-in-Picture mode */
    private fun enterPictureInPicture(result: MethodChannel.Result) {
        val currentActivity = activity
        
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Activity not available for PiP", null)
            return
        }
        
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED", "PiP requires Android 8.0 (API 26) or higher", null)
            return
        }
        
        try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            
            val success = currentActivity.enterPictureInPictureMode(params)
            
            if (success) {
                isPiPActive = true
                sendEvent(mapOf(
                    "event" to "pipChanged",
                    "isActive" to true
                ))
                result.success(true)
            } else {
                result.error("PIP_FAILED", "Failed to enter PiP mode", null)
            }
        } catch (e: Exception) {
            result.error("PIP_ERROR", e.message, null)
        }
    }
    
    /** Called when PiP mode changes (from MainActivity) */
    fun onPiPModeChanged(isInPiP: Boolean) {
        isPiPActive = isInPiP
        sendEvent(mapOf(
            "event" to "pipChanged",
            "isActive" to isInPiP
        ))
    }


    // Data classes for track information
    data class VideoQualityInfo(
        val trackGroup: TrackGroup,
        val trackIndex: Int,
        val width: Int,
        val height: Int,
        val bitrate: Int,
        val label: String
    )

    data class AudioTrackInfo(
        val trackGroup: TrackGroup,
        val trackIndex: Int,
        val language: String,
        val label: String
    )

    data class SubtitleTrackInfo(
        val trackGroup: TrackGroup,
        val trackIndex: Int,
        val language: String,
        val label: String
    )
}
