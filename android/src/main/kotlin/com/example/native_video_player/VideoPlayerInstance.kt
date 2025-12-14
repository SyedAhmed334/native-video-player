package com.example.native_video_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.Surface
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSink
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry
import java.util.UUID

/**
 * VideoPlayerInstance - Encapsulates a single ExoPlayer instance
 * Each instance has its own player, texture, and event sink
 * Supports optional caching via VideoCacheManager
 */
@UnstableApi
class VideoPlayerInstance(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    val playerId: String,
    private val enableCaching: Boolean = true
) {
    companion object {
        private const val TAG = "VideoPlayerInstance"
    }

    // ExoPlayer components
    private var player: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    
    // Event streaming
    var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var positionUpdateRunnable: Runnable? = null
    
    // Track information
    private var availableQualities = mutableListOf<VideoQualityInfo>()
    private var availableAudioTracks = mutableListOf<AudioTrackInfo>()
    private var availableSubtitles = mutableListOf<SubtitleTrackInfo>()
    private var selectedQualityIndex = -1
    private var selectedAudioIndex = -1
    private var selectedSubtitleIndex = -1
    private var isAutoQuality = true
    
    // State tracking
    private var isBuffering = false
    private var currentUrl: String? = null
    private var isDisposed = false
    
    // Activity for PiP
    private var activity: Activity? = null

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    /**
     * Check if player is disposed
     */
    fun isDisposed(): Boolean = isDisposed

    /**
     * Initialize player with URL
     * Returns texture ID for Flutter rendering, or -1 on failure
     */
    fun initialize(url: String): Long {
        if (isDisposed) {
            android.util.Log.e(TAG, "[$playerId] Cannot initialize - player is disposed")
            return -1L
        }
        
        return try {
            currentUrl = url
            
            // Create texture with null check
            textureEntry = textureRegistry.createSurfaceTexture()
            if (textureEntry == null) {
                android.util.Log.e(TAG, "[$playerId] Failed to create texture entry")
                sendEvent(mapOf("event" to "error", "message" to "Failed to create texture"))
                return -1L
            }
            
            val surfaceTexture = textureEntry?.surfaceTexture()
            if (surfaceTexture == null) {
                android.util.Log.e(TAG, "[$playerId] Failed to get surface texture")
                sendEvent(mapOf("event" to "error", "message" to "Failed to get surface texture"))
                return -1L
            }
            
            surface = Surface(surfaceTexture)
            
            // Create track selector
            val trackSelectionFactory = AdaptiveTrackSelection.Factory()
            trackSelector = DefaultTrackSelector(context, trackSelectionFactory).apply {
                setParameters(
                    buildUponParameters()
                        .setMaxVideoSizeSd()
                        .setPreferredAudioLanguage("en")
                        .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                        .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                        .build()
                )
            }
            
            // Configure load control with back buffer
            val loadControl = DefaultLoadControl.Builder()
                .setBackBuffer(60_000, true)
                .setBufferDurationsMs(15_000, 50_000, 2_500, 5_000)
                .build()
            
            // Audio attributes
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build()
            
            // Create media source factory with optional caching
            val mediaSourceFactory = createMediaSourceFactory()
            
            // Build player
            player = ExoPlayer.Builder(context)
                .setTrackSelector(trackSelector!!)
                .setLoadControl(loadControl)
                .setAudioAttributes(audioAttributes, true)
                .setMediaSourceFactory(mediaSourceFactory)
                .build().apply {
                    setVideoSurface(surface)
                    addListener(createPlayerListener())
                    setMediaItem(MediaItem.fromUri(url))
                    prepare()
                }
            
            startPositionUpdates()
            
            android.util.Log.d(TAG, "[$playerId] Initialized with texture: ${textureEntry?.id()}, caching: $enableCaching")
            textureEntry?.id() ?: -1L
        } catch (e: Exception) {
            android.util.Log.e(TAG, "[$playerId] Initialization failed: ${e.message}", e)
            sendEvent(mapOf("event" to "error", "message" to "Initialization failed: ${e.message}"))
            dispose()
            -1L
        }
    }

    /**
     * Initialize player with DRM protected content
     * @param url Video URL (DASH/HLS with DRM)
     * @param drmType "widevine", "playready", or "clearkey"
     * @param licenseUrl License server URL
     * @param headers Optional headers for license requests
     * Returns texture ID for Flutter rendering, or -1 on failure
     */
    fun initializeWithDrm(
        url: String,
        drmType: String,
        licenseUrl: String,
        headers: Map<String, String>? = null
    ): Long {
        if (isDisposed) {
            android.util.Log.e(TAG, "[$playerId] Cannot initialize DRM - player is disposed")
            return -1L
        }
        
        return try {
            currentUrl = url
            
            // Create texture
            textureEntry = textureRegistry.createSurfaceTexture()
            if (textureEntry == null) {
                android.util.Log.e(TAG, "[$playerId] Failed to create texture entry")
                sendEvent(mapOf("event" to "error", "message" to "Failed to create texture"))
                return -1L
            }
            
            val surfaceTexture = textureEntry?.surfaceTexture()
            if (surfaceTexture == null) {
                android.util.Log.e(TAG, "[$playerId] Failed to get surface texture")
                return -1L
            }
            
            surface = Surface(surfaceTexture)
            
            // Get DRM UUID based on type
            val drmUuid = when (drmType.lowercase()) {
                "widevine" -> C.WIDEVINE_UUID
                "playready" -> C.PLAYREADY_UUID
                "clearkey" -> C.CLEARKEY_UUID
                else -> {
                    android.util.Log.e(TAG, "[$playerId] Unknown DRM type: $drmType")
                    sendEvent(mapOf("event" to "error", "message" to "Unknown DRM type: $drmType"))
                    return -1L
                }
            }
            
            // Create HTTP data source factory for license requests
            val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            headers?.let { hdrs ->
                httpDataSourceFactory.setDefaultRequestProperties(hdrs)
            }
            
            // Create DRM callback
            val drmCallback = HttpMediaDrmCallback(licenseUrl, httpDataSourceFactory)
            
            // Add headers to DRM callback if provided
            headers?.forEach { (key, value) ->
                drmCallback.setKeyRequestProperty(key, value)
            }
            
            // Create DRM session manager
            val drmSessionManager = DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(drmUuid, FrameworkMediaDrm.DEFAULT_PROVIDER)
                .build(drmCallback)
            
            // Create track selector
            val trackSelectionFactory = AdaptiveTrackSelection.Factory()
            trackSelector = DefaultTrackSelector(context, trackSelectionFactory).apply {
                setParameters(
                    buildUponParameters()
                        .setMaxVideoSizeSd()
                        .setPreferredAudioLanguage("en")
                        .build()
                )
            }
            
            val loadControl = DefaultLoadControl.Builder()
                .setBackBuffer(60_000, true)
                .setBufferDurationsMs(15_000, 50_000, 2_500, 5_000)
                .build()
            
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build()
            
            // Create media source factory with DRM
            val mediaSourceFactory = DefaultMediaSourceFactory(context)
                .setDrmSessionManagerProvider { drmSessionManager }
            
            // Build DRM-protected media item
            val mediaItem = MediaItem.Builder()
                .setUri(url)
                .setDrmConfiguration(
                    MediaItem.DrmConfiguration.Builder(drmUuid)
                        .setLicenseUri(licenseUrl)
                        .setLicenseRequestHeaders(headers ?: emptyMap())
                        .build()
                )
                .build()
            
            // Build player
            player = ExoPlayer.Builder(context)
                .setTrackSelector(trackSelector!!)
                .setLoadControl(loadControl)
                .setAudioAttributes(audioAttributes, true)
                .setMediaSourceFactory(mediaSourceFactory)
                .build().apply {
                    setVideoSurface(surface)
                    addListener(createPlayerListener())
                    setMediaItem(mediaItem)
                    prepare()
                }
            
            startPositionUpdates()
            
            android.util.Log.d(TAG, "[$playerId] Initialized with DRM ($drmType), texture: ${textureEntry?.id()}")
            sendEvent(mapOf("event" to "drmInitialized", "type" to drmType))
            textureEntry?.id() ?: -1L
        } catch (e: Exception) {
            android.util.Log.e(TAG, "[$playerId] DRM initialization failed: ${e.message}", e)
            sendEvent(mapOf("event" to "error", "message" to "DRM initialization failed: ${e.message}"))
            dispose()
            -1L
        }
    }

    /**
     * Create media source factory with caching support
     */
    private fun createMediaSourceFactory(): DefaultMediaSourceFactory {
        val upstreamFactory = DefaultDataSource.Factory(context)
        
        return if (enableCaching) {
            val cache = VideoCacheManager.getCache(context)
            if (cache != null) {
                val cacheDataSourceFactory = CacheDataSource.Factory()
                    .setCache(cache)
                    .setUpstreamDataSourceFactory(upstreamFactory)
                    .setCacheWriteDataSinkFactory(CacheDataSink.Factory().setCache(cache).setFragmentSize(C.LENGTH_UNSET.toLong()))
                    .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
                
                android.util.Log.d(TAG, "[$playerId] Using cached media source")
                DefaultMediaSourceFactory(context).setDataSourceFactory(cacheDataSourceFactory)
            } else {
                android.util.Log.d(TAG, "[$playerId] Cache unavailable, using default source")
                DefaultMediaSourceFactory(context).setDataSourceFactory(upstreamFactory)
            }
        } else {
            DefaultMediaSourceFactory(context).setDataSourceFactory(upstreamFactory)
        }
    }

    /**
     * Preload video without playing (for feed scenarios)
     */
    fun preload(url: String): Long {
        val textureId = initialize(url)
        player?.playWhenReady = false
        android.util.Log.d(TAG, "[$playerId] Preloaded: $url")
        return textureId
    }

    private fun createPlayerListener(): Player.Listener {
        return object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                handlePlaybackStateChanged(playbackState)
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
        }
    }

    fun play() {
        player?.play()
    }

    fun pause() {
        player?.pause()
    }

    fun seekTo(position: Long) {
        player?.seekTo(position)
    }

    fun setVolume(volume: Double) {
        player?.volume = volume.toFloat()
    }

    fun setSpeed(speed: Double) {
        player?.setPlaybackSpeed(speed.toFloat())
    }

    fun getDuration(): Long {
        val duration = player?.duration ?: C.TIME_UNSET
        return if (duration == C.TIME_UNSET) 0L else duration
    }

    fun getCurrentPosition(): Long {
        return player?.currentPosition ?: 0L
    }

    fun getBufferedPosition(): Long {
        return player?.bufferedPosition ?: 0L
    }

    // MARK: - Picture-in-Picture
    
    /**
     * Enter Picture-in-Picture mode (Android 8.0+)
     * @return true if PiP was entered, false otherwise
     */
    fun enterPiP(): Boolean {
        val currentActivity = activity ?: return false
        
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            android.util.Log.w(TAG, "[$playerId] PiP requires Android 8.0 (API 26)+")
            return false
        }
        
        return try {
            val aspectRatio = Rational(16, 9) // Default 16:9 aspect ratio
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(aspectRatio)
                .build()
            
            currentActivity.enterPictureInPictureMode(params)
            sendEvent(mapOf("event" to "pipChanged", "isActive" to true))
            android.util.Log.d(TAG, "[$playerId] Entered PiP mode")
            true
        } catch (e: Exception) {
            android.util.Log.e(TAG, "[$playerId] Failed to enter PiP: ${e.message}")
            sendEvent(mapOf("event" to "pipError", "message" to (e.message ?: "Unknown error")))
            false
        }
    }

    fun getAvailableQualities(): List<Map<String, Any>> {
        updateAvailableTracks()
        return availableQualities.mapIndexed { index, quality ->
            mapOf(
                "index" to index,
                "width" to quality.width,
                "height" to quality.height,
                "bitrate" to quality.bitrate,
                "label" to quality.label
            )
        }
    }

    fun setQuality(index: Int) {
        if (index < 0 || index >= availableQualities.size) return
        
        val quality = availableQualities[index]
        trackSelector?.setParameters(
            trackSelector!!.buildUponParameters()
                .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                .setMaxVideoSize(quality.width, quality.height)
                .setMinVideoSize(quality.width, quality.height)
                .build()
        )
        selectedQualityIndex = index
        isAutoQuality = false
        
        sendEvent(mapOf(
            "event" to "qualityChanged",
            "index" to index,
            "isAuto" to false
        ))
    }

    fun setAutoQuality() {
        trackSelector?.setParameters(
            trackSelector!!.buildUponParameters()
                .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                .clearVideoSizeConstraints()
                .setMaxVideoSizeSd()
                .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                .build()
        )
        selectedQualityIndex = -1
        isAutoQuality = true
        
        sendEvent(mapOf(
            "event" to "qualityChanged",
            "index" to -1,
            "isAuto" to true
        ))
    }

    fun getAvailableAudioTracks(): List<Map<String, Any>> {
        updateAvailableTracks()
        return availableAudioTracks.mapIndexed { index, audio ->
            mapOf(
                "index" to index,
                "language" to audio.language,
                "label" to audio.label
            )
        }
    }

    fun setAudioTrack(index: Int) {
        if (index < 0 || index >= availableAudioTracks.size) return
        
        val audio = availableAudioTracks[index]
        val override = androidx.media3.common.TrackSelectionOverride(
            audio.trackGroup,
            listOf(audio.trackIndex)
        )
        
        trackSelector?.setParameters(
            trackSelector!!.buildUponParameters()
                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                .addOverride(override)
                .build()
        )
        selectedAudioIndex = index
        
        sendEvent(mapOf("event" to "audioChanged", "index" to index))
    }

    fun getAvailableSubtitles(): List<Map<String, Any>> {
        updateAvailableTracks()
        return availableSubtitles.mapIndexed { index, subtitle ->
            mapOf(
                "index" to index,
                "language" to subtitle.language,
                "label" to subtitle.label
            )
        }
    }

    fun setSubtitle(index: Int) {
        if (index == -1) {
            trackSelector?.setParameters(
                trackSelector!!.buildUponParameters()
                    .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                    .build()
            )
        } else if (index >= 0 && index < availableSubtitles.size) {
            val subtitle = availableSubtitles[index]
            trackSelector?.setParameters(
                trackSelector!!.buildUponParameters()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                    .setPreferredTextLanguage(subtitle.language)
                    .build()
            )
        }
        selectedSubtitleIndex = index
        sendEvent(mapOf("event" to "subtitleChanged", "index" to index))
    }

    @Synchronized
    fun dispose() {
        if (isDisposed) {
            android.util.Log.d(TAG, "[$playerId] Already disposed, skipping")
            return
        }
        
        isDisposed = true
        android.util.Log.d(TAG, "[$playerId] Disposing...")
        
        try {
            stopPositionUpdates()
            
            player?.let { p ->
                p.stop()
                p.clearMediaItems()
                p.release()
            }
            player = null
            
            surface?.release()
            surface = null
            
            textureEntry?.release()
            textureEntry = null
            
            trackSelector = null
            availableQualities.clear()
            availableAudioTracks.clear()
            availableSubtitles.clear()
            
            android.util.Log.d(TAG, "[$playerId] Disposed")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "[$playerId] Error during dispose: ${e.message}", e)
        }
    }

    private fun updateAvailableTracks() {
        val tracks = player?.currentTracks ?: return
        
        availableQualities.clear()
        availableAudioTracks.clear()
        availableSubtitles.clear()
        
        tracks.groups.forEach { trackGroup ->
            when (trackGroup.type) {
                C.TRACK_TYPE_VIDEO -> {
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
                    }
                }
                C.TRACK_TYPE_AUDIO -> {
                    for (i in 0 until trackGroup.length) {
                        val format = trackGroup.getTrackFormat(i)
                        val language = format.language ?: "Unknown"
                        availableAudioTracks.add(AudioTrackInfo(
                            trackGroup = trackGroup.mediaTrackGroup,
                            trackIndex = i,
                            language = language,
                            label = format.label ?: language
                        ))
                    }
                }
                C.TRACK_TYPE_TEXT -> {
                    for (i in 0 until trackGroup.length) {
                        val format = trackGroup.getTrackFormat(i)
                        val language = format.language ?: "Unknown"
                        availableSubtitles.add(SubtitleTrackInfo(
                            trackGroup = trackGroup.mediaTrackGroup,
                            trackIndex = i,
                            language = language,
                            label = format.label ?: language
                        ))
                    }
                }
            }
        }
    }

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

    private fun startPositionUpdates() {
        if (positionUpdateRunnable != null) return
        
        positionUpdateRunnable = object : Runnable {
            override fun run() {
                player?.let { p ->
                    val duration = p.duration
                    sendEvent(mapOf(
                        "event" to "position",
                        "position" to p.currentPosition,
                        "bufferedPosition" to p.bufferedPosition,
                        "duration" to if (duration == C.TIME_UNSET) 0L else duration
                    ))
                }
                mainHandler.postDelayed(this, 500)
            }
        }
        mainHandler.post(positionUpdateRunnable!!)
    }

    private fun stopPositionUpdates() {
        positionUpdateRunnable?.let {
            mainHandler.removeCallbacks(it)
            positionUpdateRunnable = null
        }
    }

    private fun sendEvent(key: String, value: Any) {
        sendEvent(mapOf(key to value))
    }

    private fun sendEvent(event: Map<String, Any>) {
        eventSink?.let { sink ->
            mainHandler.post { sink.success(event) }
        }
    }

    // Data classes
    data class VideoQualityInfo(
        val trackGroup: androidx.media3.common.TrackGroup,
        val trackIndex: Int,
        val width: Int,
        val height: Int,
        val bitrate: Int,
        val label: String
    )

    data class AudioTrackInfo(
        val trackGroup: androidx.media3.common.TrackGroup,
        val trackIndex: Int,
        val language: String,
        val label: String
    )

    data class SubtitleTrackInfo(
        val trackGroup: androidx.media3.common.TrackGroup,
        val trackIndex: Int,
        val language: String,
        val label: String
    )
}
