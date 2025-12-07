package com.example.custom_video_player

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    
    private var videoPlayerPlugin: VideoPlayerPlugin? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the video player plugin and store reference
        videoPlayerPlugin = VideoPlayerPlugin.registerWithActivity(flutterEngine, this)
    }
    
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Auto-enter PiP when user presses home while video is playing
        // This is optional - you can remove this if you only want manual PiP
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()
                enterPictureInPictureMode(params)
            } catch (e: Exception) {
                // Ignore if PiP not supported or fails
            }
        }
    }
    
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Notify the plugin about PiP mode changes
        videoPlayerPlugin?.onPiPModeChanged(isInPictureInPictureMode)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        videoPlayerPlugin = null
    }
}
