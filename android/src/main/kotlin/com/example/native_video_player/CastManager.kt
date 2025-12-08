package com.example.native_video_player

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManager
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import io.flutter.plugin.common.EventChannel

/**
 * CastManager - Handles Chromecast device discovery and media casting
 */
class CastManager(
    private val context: Context,
    private var activity: Activity?
) {
    companion object {
        private const val TAG = "CastManager"
    }
    
    // Cast components
    private var castContext: CastContext? = null
    private var sessionManager: SessionManager? = null
    private var castSession: CastSession? = null
    private var remoteMediaClient: RemoteMediaClient? = null
    
    // MediaRouter for device discovery
    private var mediaRouter: MediaRouter? = null
    private var mediaRouteSelector: MediaRouteSelector? = null
    
    // State
    private var isInitialized = false
    private var isCasting = false
    private var currentMediaUrl: String? = null
    
    // Event sink for Flutter
    var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    
    // Session listener
    private val sessionManagerListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {
            sendEvent(mapOf("event" to "castStateChanged", "state" to "connecting"))
        }
        
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            castSession = session
            remoteMediaClient = session.remoteMediaClient
            isCasting = true
            sendEvent(mapOf(
                "event" to "castStateChanged",
                "state" to "connected",
                "deviceName" to (session.castDevice?.friendlyName ?: "Unknown")
            ))
            
            // If we have pending media, load it
            currentMediaUrl?.let { loadMedia(it) }
        }
        
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            sendEvent(mapOf("event" to "castError", "code" to error, "message" to "Session start failed"))
        }
        
        override fun onSessionEnding(session: CastSession) {
            sendEvent(mapOf("event" to "castStateChanged", "state" to "disconnecting"))
        }
        
        override fun onSessionEnded(session: CastSession, error: Int) {
            castSession = null
            remoteMediaClient = null
            isCasting = false
            sendEvent(mapOf("event" to "castStateChanged", "state" to "notConnected"))
        }
        
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            castSession = session
            remoteMediaClient = session.remoteMediaClient
            isCasting = true
            sendEvent(mapOf("event" to "castStateChanged", "state" to "connected"))
        }
        
        override fun onSessionResumeFailed(session: CastSession, error: Int) {}
        override fun onSessionSuspended(session: CastSession, reason: Int) {}
    }
    
    /**
     * Initialize Cast SDK
     */
    fun initialize(): Boolean {
        if (isInitialized) return true
        
        return try {
            castContext = CastContext.getSharedInstance(context)
            sessionManager = castContext?.sessionManager
            
            // Add session listener
            sessionManager?.addSessionManagerListener(sessionManagerListener, CastSession::class.java)
            
            // Setup MediaRouter for device discovery
            mediaRouter = MediaRouter.getInstance(context)
            mediaRouteSelector = MediaRouteSelector.Builder()
                .addControlCategory(CastMediaControlIntent.categoryForCast(
                    CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID
                ))
                .build()
            
            isInitialized = true
            android.util.Log.d(TAG, "Cast SDK initialized")
            sendEvent(mapOf("event" to "castInitialized"))
            true
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to initialize Cast SDK: ${e.message}")
            sendEvent(mapOf("event" to "castError", "message" to "Cast SDK initialization failed"))
            false
        }
    }
    
    /**
     * Get list of available cast devices
     */
    fun getDevices(): List<Map<String, Any>> {
        val devices = mutableListOf<Map<String, Any>>()
        
        mediaRouter?.let { router ->
            mediaRouteSelector?.let { selector ->
                for (route in router.routes) {
                    if (route.matchesSelector(selector) && !route.isDefault) {
                        devices.add(mapOf(
                            "id" to route.id,
                            "name" to route.name,
                            "description" to (route.description ?: ""),
                            "isConnected" to route.isSelected
                        ))
                    }
                }
            }
        }
        
        return devices
    }
    
    /**
     * Connect to a cast device by ID
     */
    fun connect(deviceId: String): Boolean {
        mediaRouter?.let { router ->
            for (route in router.routes) {
                if (route.id == deviceId) {
                    router.selectRoute(route)
                    return true
                }
            }
        }
        return false
    }
    
    /**
     * Disconnect from current cast session
     */
    fun disconnect() {
        sessionManager?.endCurrentSession(true)
        isCasting = false
    }
    
    /**
     * Load media to cast device
     */
    fun loadMedia(
        url: String,
        title: String? = null,
        subtitle: String? = null,
        imageUrl: String? = null,
        startPosition: Long = 0
    ): Boolean {
        currentMediaUrl = url
        
        if (!isCasting || remoteMediaClient == null) {
            android.util.Log.d(TAG, "Not casting yet, will load when connected")
            return false
        }
        
        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE).apply {
            title?.let { putString(MediaMetadata.KEY_TITLE, it) }
            subtitle?.let { putString(MediaMetadata.KEY_SUBTITLE, it) }
            // Add image if provided
            // imageUrl?.let { addImage(WebImage(Uri.parse(it))) }
        }
        
        val mediaInfo = MediaInfo.Builder(url)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType("application/x-mpegURL") // HLS
            .setMetadata(metadata)
            .build()
        
        val loadRequest = MediaLoadRequestData.Builder()
            .setMediaInfo(mediaInfo)
            .setAutoplay(true)
            .setCurrentTime(startPosition)
            .build()
        
        remoteMediaClient?.load(loadRequest)
        sendEvent(mapOf("event" to "castMediaLoaded", "url" to url))
        
        return true
    }
    
    /**
     * Control remote playback
     */
    fun play() {
        remoteMediaClient?.play()
    }
    
    fun pause() {
        remoteMediaClient?.pause()
    }
    
    fun seek(positionMs: Long) {
        remoteMediaClient?.seek(positionMs)
    }
    
    fun setVolume(volume: Double) {
        remoteMediaClient?.setStreamVolume(volume)
    }
    
    fun stop() {
        remoteMediaClient?.stop()
    }
    
    /**
     * Get current cast state
     */
    fun getCastState(): String {
        return when {
            !isInitialized -> "notInitialized"
            isCasting -> "connected"
            else -> "notConnected"
        }
    }
    
    /**
     * Check if currently casting
     */
    fun isCasting(): Boolean = isCasting
    
    /**
     * Get current device name
     */
    fun getConnectedDeviceName(): String? {
        return castSession?.castDevice?.friendlyName
    }
    
    fun setActivity(activity: Activity?) {
        this.activity = activity
    }
    
    /**
     * Clean up
     */
    fun dispose() {
        sessionManager?.removeSessionManagerListener(sessionManagerListener, CastSession::class.java)
        mediaRouter = null
        castContext = null
        isInitialized = false
    }
    
    private fun sendEvent(data: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(data)
        }
    }
}
