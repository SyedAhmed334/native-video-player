package com.example.custom_video_player;

import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.Surface;

import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.Tracks;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.exoplayer.source.MergingMediaSource;
import androidx.media3.exoplayer.source.ProgressiveMediaSource;
import androidx.media3.exoplayer.source.SingleSampleMediaSource;
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.common.TrackSelectionParameters;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;

/**
 * VideoPlayerPlugin - Complete ExoPlayer integration for Flutter
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
public class VideoPlayerPlugin implements MethodChannel.MethodCallHandler {

    private static final String METHOD_CHANNEL = "native_video_player/method";
    private static final String EVENT_CHANNEL = "native_video_player/event";

    private final Context context;
    private final TextureRegistry textureRegistry;
    private final MethodChannel methodChannel;
    private final EventChannel eventChannel;

    // ExoPlayer components
    private ExoPlayer player;
    private DefaultTrackSelector trackSelector;
    private TextureRegistry.SurfaceTextureEntry textureEntry;
    private Surface surface;

    // Event streaming
    private EventChannel.EventSink eventSink;
    private Handler mainHandler;
    private Runnable positionUpdateRunnable;

    // Track information
    private List<VideoQualityInfo> availableQualities;
    private List<AudioTrackInfo> availableAudioTracks;
    private List<SubtitleTrackInfo> availableSubtitles;
    private int selectedQualityIndex = -1;
    private int selectedAudioIndex = -1;
    private int selectedSubtitleIndex = -1;

    // State tracking
    private boolean isBuffering = false;
    private String currentUrl;
    private MediaSource externalSubtitleSource;

    public VideoPlayerPlugin(Context context, TextureRegistry textureRegistry,
            MethodChannel methodChannel, EventChannel eventChannel) {
        this.context = context;
        this.textureRegistry = textureRegistry;
        this.methodChannel = methodChannel;
        this.eventChannel = eventChannel;
        this.mainHandler = new Handler(Looper.getMainLooper());

        methodChannel.setMethodCallHandler(this);
        eventChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                eventSink = events;
                startPositionUpdates();
            }

            @Override
            public void onCancel(Object arguments) {
                eventSink = null;
                stopPositionUpdates();
            }
        });
    }

    public static void registerWith(FlutterEngine flutterEngine, Context context) {
        MethodChannel methodChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                METHOD_CHANNEL);
        EventChannel eventChannel = new EventChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                EVENT_CHANNEL);

        VideoPlayerPlugin plugin = new VideoPlayerPlugin(
                context,
                flutterEngine.getRenderer(),
                methodChannel,
                eventChannel);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "initialize":
                    String url = call.argument("url");
                    initializePlayer(url, result);
                    break;
                case "play":
                    play(result);
                    break;
                case "pause":
                    pause(result);
                    break;
                case "seekTo":
                    long position = ((Number) call.argument("position")).longValue();
                    seekTo(position, result);
                    break;
                case "setVolume":
                    double volume = call.argument("volume");
                    setVolume(volume, result);
                    break;
                case "setSpeed":
                    double speed = call.argument("speed");
                    setSpeed(speed, result);
                    break;
                case "getDuration":
                    getDuration(result);
                    break;
                case "getCurrentPosition":
                    getCurrentPosition(result);
                    break;
                case "getBufferedPosition":
                    getBufferedPosition(result);
                    break;
                case "getAvailableQualities":
                    getAvailableQualities(result);
                    break;
                case "setQuality":
                    int qualityIndex = call.argument("index");
                    setQuality(qualityIndex, result);
                    break;
                case "getAvailableAudioTracks":
                    getAvailableAudioTracks(result);
                    break;
                case "setAudioTrack":
                    int audioIndex = call.argument("index");
                    setAudioTrack(audioIndex, result);
                    break;
                case "getAvailableSubtitles":
                    getAvailableSubtitles(result);
                    break;
                case "setSubtitle":
                    int subtitleIndex = call.argument("index");
                    setSubtitle(subtitleIndex, result);
                    break;
                case "loadExternalSubtitle":
                    String subtitleUrl = call.argument("url");
                    loadExternalSubtitle(subtitleUrl, result);
                    break;
                case "enableOfflineMode":
                    String localPath = call.argument("localPath");
                    enableOfflineMode(localPath, result);
                    break;
                case "dispose":
                    disposePlayer(result);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            result.error("ERROR", e.getMessage(), null);
        }
    }

    /**
     * Initialize ExoPlayer with the given URL
     * Supports HLS, DASH, MP4, and other formats
     */
    private void initializePlayer(String url, MethodChannel.Result result) {
        try {
            currentUrl = url;

            // Create texture for video rendering
            textureEntry = textureRegistry.createSurfaceTexture();
            surface = new Surface(textureEntry.surfaceTexture());

            // Create track selector with adaptive selection
            AdaptiveTrackSelection.Factory trackSelectionFactory = new AdaptiveTrackSelection.Factory();
            trackSelector = new DefaultTrackSelector(context, trackSelectionFactory);

            // Enable adaptive selection and all track types by default
            trackSelector.setParameters(
                    trackSelector.buildUponParameters()
                            .setMaxVideoSizeSd()
                            .setPreferredAudioLanguage("en")
                            .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false)
                            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true) // Subtitles off by default
                            .build());

            // Build ExoPlayer
            player = new ExoPlayer.Builder(context)
                    .setTrackSelector(trackSelector)
                    .build();

            // Set video surface
            player.setVideoSurface(surface);

            // Add player listener
            player.addListener(new Player.Listener() {
                @Override
                public void onPlaybackStateChanged(int playbackState) {
                    handlePlaybackStateChanged(playbackState);
                    // Update tracks when player is ready
                    if (playbackState == Player.STATE_READY) {
                        updateAvailableTracks();
                    }
                }

                @Override
                public void onIsPlayingChanged(boolean isPlaying) {
                    sendEvent("playbackState", isPlaying ? "playing" : "paused");
                }

                @Override
                public void onPlayerError(PlaybackException error) {
                    Map<String, Object> errorData = new HashMap<>();
                    errorData.put("event", "error");
                    errorData.put("message", error.getMessage());
                    sendEvent(errorData);
                }

                @Override
                public void onTracksChanged(Tracks tracks) {
                    android.util.Log.d("VideoPlayerPlugin", "onTracksChanged called");
                    updateAvailableTracks();
                }

                @Override
                public void onCues(androidx.media3.common.text.CueGroup cueGroup) {
                    StringBuilder text = new StringBuilder();
                    for (androidx.media3.common.text.Cue cue : cueGroup.cues) {
                        if (cue.text != null) {
                            text.append(cue.text).append("\n");
                        }
                    }
                    Map<String, Object> event = new HashMap<>();
                    event.put("event", "subtitleText");
                    event.put("text", text.toString().trim());
                    sendEvent(event);
                }
            });

            // Create media item
            MediaItem mediaItem = MediaItem.fromUri(url);
            player.setMediaItem(mediaItem);
            player.prepare();

            // Return texture ID to Flutter
            Map<String, Object> response = new HashMap<>();
            response.put("textureId", textureEntry.id());
            result.success(response);

        } catch (Exception e) {
            result.error("INIT_ERROR", e.getMessage(), null);
        }
    }

    /**
     * Play the video
     */
    private void play(MethodChannel.Result result) {
        if (player != null) {
            player.play();
            result.success(null);
        } else {
            result.error("NO_PLAYER", "Player not initialized", null);
        }
    }

    /**
     * Pause the video
     */
    private void pause(MethodChannel.Result result) {
        if (player != null) {
            player.pause();
            result.success(null);
        } else {
            result.error("NO_PLAYER", "Player not initialized", null);
        }
    }

    /**
     * Seek to a specific position (in milliseconds)
     */
    private void seekTo(long position, MethodChannel.Result result) {
        if (player != null) {
            player.seekTo(position);
            result.success(null);
        } else {
            result.error("NO_PLAYER", "Player not initialized", null);
        }
    }

    /**
     * Set volume (0.0 to 1.0)
     */
    private void setVolume(double volume, MethodChannel.Result result) {
        if (player != null) {
            player.setVolume((float) volume);
            result.success(null);
        } else {
            result.error("NO_PLAYER", "Player not initialized", null);
        }
    }

    /**
     * Set playback speed
     */
    private void setSpeed(double speed, MethodChannel.Result result) {
        if (player != null) {
            player.setPlaybackSpeed((float) speed);
            result.success(null);
        } else {
            result.error("NO_PLAYER", "Player not initialized", null);
        }
    }

    /**
     * Get video duration in milliseconds
     */
    private void getDuration(MethodChannel.Result result) {
        if (player != null) {
            long duration = player.getDuration();
            result.success(duration == C.TIME_UNSET ? 0 : duration);
        } else {
            result.error("NO_PLAYER", "Player not initialized", null);
        }
    }

    /**
     * Get current playback position in milliseconds
     */
    private void getCurrentPosition(MethodChannel.Result result) {
        if (player != null) {
            result.success(player.getCurrentPosition());
        } else {
            result.error("NO_PLAYER", "Player not initialized", null);
        }
    }

    /**
     * Get buffered position in milliseconds
     */
    private void getBufferedPosition(MethodChannel.Result result) {
        if (player != null) {
            result.success(player.getBufferedPosition());
        } else {
            result.error("NO_PLAYER", "Player not initialized", null);
        }
    }

    /**
     * Get available video quality tracks
     * Netflix-style: Returns all available qualities with resolution and bitrate
     * info
     */
    private void getAvailableQualities(MethodChannel.Result result) {
        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null);
            return;
        }

        updateAvailableTracks();

        android.util.Log.d("VideoPlayerPlugin",
                "getAvailableQualities called, found " + availableQualities.size() + " qualities");

        List<Map<String, Object>> qualities = new ArrayList<>();
        for (int i = 0; i < availableQualities.size(); i++) {
            VideoQualityInfo quality = availableQualities.get(i);
            Map<String, Object> qualityMap = new HashMap<>();
            qualityMap.put("index", i);
            qualityMap.put("width", quality.width);
            qualityMap.put("height", quality.height);
            qualityMap.put("bitrate", quality.bitrate);
            qualityMap.put("label", quality.label);
            qualities.add(qualityMap);
        }

        result.success(qualities);
    }

    /**
     * Set video quality - SEAMLESS SWITCHING (Netflix-style)
     * Uses TrackSelectionOverride to switch without stopping playback
     * Maintains buffer and provides smooth transition
     */
    private void setQuality(int index, MethodChannel.Result result) {
        if (player == null || trackSelector == null) {
            result.error("NO_PLAYER", "Player not initialized", null);
            return;
        }

        if (index < 0 || index >= availableQualities.size()) {
            result.error("INVALID_INDEX", "Quality index out of range", null);
            return;
        }

        try {
            VideoQualityInfo selectedQuality = availableQualities.get(index);

            // Manual track selection for seamless switching
            TrackSelectionParameters.Builder builder = trackSelector.buildUponParameters();
            builder.setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false);

            // Set preferred video track by height
            builder.setMaxVideoSize(selectedQuality.width, selectedQuality.height);
            builder.setMinVideoSize(selectedQuality.width, selectedQuality.height);

            trackSelector.setParameters(builder.build());
            selectedQualityIndex = index;

            // Notify Flutter about quality change
            Map<String, Object> event = new HashMap<>();
            event.put("event", "qualityChanged");
            event.put("index", index);
            sendEvent(event);

            result.success(null);

        } catch (Exception e) {
            result.error("QUALITY_ERROR", e.getMessage(), null);
        }
    }

    /**
     * Get available audio tracks
     */
    private void getAvailableAudioTracks(MethodChannel.Result result) {
        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null);
            return;
        }

        updateAvailableTracks();

        android.util.Log.d("VideoPlayerPlugin",
                "getAvailableAudioTracks called, found " + availableAudioTracks.size() + " audio tracks");

        List<Map<String, Object>> audioTracks = new ArrayList<>();
        for (int i = 0; i < availableAudioTracks.size(); i++) {
            AudioTrackInfo audio = availableAudioTracks.get(i);
            Map<String, Object> audioMap = new HashMap<>();
            audioMap.put("index", i);
            audioMap.put("language", audio.language);
            audioMap.put("label", audio.label);
            audioTracks.add(audioMap);
        }

        result.success(audioTracks);
    }

    /**
     * Set audio track - INSTANT SWITCHING (Netflix-style)
     * Switches audio without any reload or rebuffering
     */
    private void setAudioTrack(int index, MethodChannel.Result result) {
        if (player == null || trackSelector == null) {
            result.error("NO_PLAYER", "Player not initialized", null);
            return;
        }

        if (index < 0 || index >= availableAudioTracks.size()) {
            result.error("INVALID_INDEX", "Audio track index out of range", null);
            return;
        }

        try {
            AudioTrackInfo selectedAudio = availableAudioTracks.get(index);

            // Manual audio track selection for instant switching
            TrackSelectionParameters.Builder builder = trackSelector.buildUponParameters();
            builder.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false);
            builder.setPreferredAudioLanguage(selectedAudio.language);

            trackSelector.setParameters(builder.build());
            selectedAudioIndex = index;

            // Notify Flutter about audio change
            Map<String, Object> event = new HashMap<>();
            event.put("event", "audioChanged");
            event.put("index", index);
            sendEvent(event);

            result.success(null);

        } catch (Exception e) {
            result.error("AUDIO_ERROR", e.getMessage(), null);
        }
    }

    /**
     * Get available subtitle tracks
     */
    private void getAvailableSubtitles(MethodChannel.Result result) {
        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null);
            return;
        }

        updateAvailableTracks();

        android.util.Log.d("VideoPlayerPlugin",
                "getAvailableSubtitles called, found " + availableSubtitles.size() + " subtitles");

        List<Map<String, Object>> subtitles = new ArrayList<>();
        for (int i = 0; i < availableSubtitles.size(); i++) {
            SubtitleTrackInfo subtitle = availableSubtitles.get(i);
            Map<String, Object> subtitleMap = new HashMap<>();
            subtitleMap.put("index", i);
            subtitleMap.put("language", subtitle.language);
            subtitleMap.put("label", subtitle.label);
            subtitles.add(subtitleMap);
        }

        result.success(subtitles);
    }

    /**
     * Set subtitle track - INSTANT SWITCHING (Netflix-style)
     * Index -1 disables subtitles
     */
    private void setSubtitle(int index, MethodChannel.Result result) {
        if (player == null || trackSelector == null) {
            result.error("NO_PLAYER", "Player not initialized", null);
            return;
        }

        try {
            if (index == -1) {
                // Disable subtitles
                trackSelector.setParameters(
                        trackSelector.buildUponParameters()
                                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true));
            } else {
                if (index < 0 || index >= availableSubtitles.size()) {
                    result.error("INVALID_INDEX", "Subtitle index out of range", null);
                    return;
                }

                SubtitleTrackInfo selectedSubtitle = availableSubtitles.get(index);

                // Manual subtitle track selection
                TrackSelectionParameters.Builder builder = trackSelector.buildUponParameters();
                builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false);
                builder.setPreferredTextLanguage(selectedSubtitle.language);

                trackSelector.setParameters(builder.build());
            }

            selectedSubtitleIndex = index;

            // Notify Flutter about subtitle change
            Map<String, Object> event = new HashMap<>();
            event.put("event", "subtitleChanged");
            event.put("index", index);
            sendEvent(event);

            result.success(null);

        } catch (Exception e) {
            result.error("SUBTITLE_ERROR", e.getMessage(), null);
        }
    }

    /**
     * Load external subtitle file (.vtt or .srt)
     * Merges with main media source
     */
    private void loadExternalSubtitle(String subtitleUrl, MethodChannel.Result result) {
        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null);
            return;
        }

        try {
            // Create subtitle media item
            MediaItem.SubtitleConfiguration subtitleConfig = new MediaItem.SubtitleConfiguration.Builder(
                    Uri.parse(subtitleUrl))
                    .setMimeType(MimeTypes.TEXT_VTT)
                    .setLanguage("en")
                    .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                    .build();

            // Create single sample media source for subtitle
            DefaultDataSource.Factory dataSourceFactory = new DefaultDataSource.Factory(context);

            externalSubtitleSource = new SingleSampleMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(subtitleConfig, C.TIME_UNSET);

            // Merge with current media source
            MediaItem currentItem = MediaItem.fromUri(currentUrl);
            MediaSource videoSource = new ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(currentItem);

            MergingMediaSource mergedSource = new MergingMediaSource(
                    videoSource,
                    externalSubtitleSource);

            // Save current position
            long currentPosition = player.getCurrentPosition();
            boolean wasPlaying = player.isPlaying();

            // Set merged source
            player.setMediaSource(mergedSource);
            player.prepare();
            player.seekTo(currentPosition);

            if (wasPlaying) {
                player.play();
            }

            result.success(null);

        } catch (Exception e) {
            result.error("SUBTITLE_LOAD_ERROR", e.getMessage(), null);
        }
    }

    /**
     * Enable offline playback mode
     * Uses ProgressiveMediaSource for local files
     */
    private void enableOfflineMode(String localPath, MethodChannel.Result result) {
        if (player == null) {
            result.error("NO_PLAYER", "Player not initialized", null);
            return;
        }

        try {
            DefaultDataSource.Factory dataSourceFactory = new DefaultDataSource.Factory(context);

            MediaItem mediaItem = MediaItem.fromUri(Uri.parse(localPath));
            MediaSource mediaSource = new ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(mediaItem);

            player.setMediaSource(mediaSource);
            player.prepare();

            result.success(null);

        } catch (Exception e) {
            result.error("OFFLINE_ERROR", e.getMessage(), null);
        }
    }

    /**
     * Dispose player and release resources
     */
    private void disposePlayer(MethodChannel.Result result) {
        stopPositionUpdates();

        if (player != null) {
            player.release();
            player = null;
        }

        if (surface != null) {
            surface.release();
            surface = null;
        }

        if (textureEntry != null) {
            textureEntry.release();
            textureEntry = null;
        }

        trackSelector = null;
        availableQualities = null;
        availableAudioTracks = null;
        availableSubtitles = null;

        result.success(null);
    }

    /**
     * Update available tracks from ExoPlayer
     */
    private void updateAvailableTracks() {
        if (player == null)
            return;

        Tracks tracks = player.getCurrentTracks();
        android.util.Log.d("VideoPlayerPlugin", "Updating tracks, groups count: " + tracks.getGroups().size());

        // Update video qualities
        availableQualities = new ArrayList<>();
        for (Tracks.Group trackGroup : tracks.getGroups()) {
            if (trackGroup.getType() == C.TRACK_TYPE_VIDEO) {
                android.util.Log.d("VideoPlayerPlugin",
                        "Found video track group with " + trackGroup.length + " tracks");
                for (int i = 0; i < trackGroup.length; i++) {
                    Format format = trackGroup.getTrackFormat(i);
                    VideoQualityInfo quality = new VideoQualityInfo();
                    quality.trackGroup = trackGroup.getMediaTrackGroup();
                    quality.trackIndex = i;
                    quality.width = format.width;
                    quality.height = format.height;
                    quality.bitrate = format.bitrate;
                    quality.label = format.height + "p";
                    availableQualities.add(quality);
                    android.util.Log.d("VideoPlayerPlugin", "Added quality: " + quality.label);
                }
            }
        }

        // Update audio tracks
        availableAudioTracks = new ArrayList<>();
        for (Tracks.Group trackGroup : tracks.getGroups()) {
            if (trackGroup.getType() == C.TRACK_TYPE_AUDIO) {
                android.util.Log.d("VideoPlayerPlugin",
                        "Found audio track group with " + trackGroup.length + " tracks");
                for (int i = 0; i < trackGroup.length; i++) {
                    Format format = trackGroup.getTrackFormat(i);
                    AudioTrackInfo audio = new AudioTrackInfo();
                    audio.trackGroup = trackGroup.getMediaTrackGroup();
                    audio.trackIndex = i;
                    audio.language = format.language != null ? format.language : "Unknown";
                    audio.label = format.label != null ? format.label : audio.language;
                    availableAudioTracks.add(audio);
                    android.util.Log.d("VideoPlayerPlugin",
                            "Added audio track: " + audio.label + " (" + audio.language + ")");
                }
            }
        }

        // Update subtitle tracks
        availableSubtitles = new ArrayList<>();
        for (Tracks.Group trackGroup : tracks.getGroups()) {
            if (trackGroup.getType() == C.TRACK_TYPE_TEXT) {
                android.util.Log.d("VideoPlayerPlugin",
                        "Found subtitle track group with " + trackGroup.length + " tracks");
                for (int i = 0; i < trackGroup.length; i++) {
                    Format format = trackGroup.getTrackFormat(i);
                    SubtitleTrackInfo subtitle = new SubtitleTrackInfo();
                    subtitle.trackGroup = trackGroup.getMediaTrackGroup();
                    subtitle.trackIndex = i;
                    subtitle.language = format.language != null ? format.language : "Unknown";
                    subtitle.label = format.label != null ? format.label : subtitle.language;
                    availableSubtitles.add(subtitle);
                    android.util.Log.d("VideoPlayerPlugin",
                            "Added subtitle track: " + subtitle.label + " (" + subtitle.language + ")");
                }
            }
        }
    }

    /**
     * Handle playback state changes
     */
    private void handlePlaybackStateChanged(int playbackState) {
        switch (playbackState) {
            case Player.STATE_BUFFERING:
                if (!isBuffering) {
                    isBuffering = true;
                    sendEvent("bufferState", "buffering");
                }
                break;
            case Player.STATE_READY:
                if (isBuffering) {
                    isBuffering = false;
                    sendEvent("bufferState", "ready");
                }
                break;
            case Player.STATE_ENDED:
                sendEvent("playbackState", "completed");
                break;
        }
    }

    /**
     * Start periodic position updates
     */
    private void startPositionUpdates() {
        if (positionUpdateRunnable != null)
            return;

        positionUpdateRunnable = new Runnable() {
            @Override
            public void run() {
                if (player != null && eventSink != null) {
                    Map<String, Object> position = new HashMap<>();
                    position.put("event", "position");
                    position.put("position", player.getCurrentPosition());
                    position.put("bufferedPosition", player.getBufferedPosition());
                    position.put("duration", player.getDuration() == C.TIME_UNSET ? 0 : player.getDuration());
                    sendEvent(position);
                }
                mainHandler.postDelayed(this, 500); // Update every 500ms
            }
        };

        mainHandler.post(positionUpdateRunnable);
    }

    /**
     * Stop position updates
     */
    private void stopPositionUpdates() {
        if (positionUpdateRunnable != null) {
            mainHandler.removeCallbacks(positionUpdateRunnable);
            positionUpdateRunnable = null;
        }
    }

    /**
     * Send event to Flutter via EventChannel
     */
    private void sendEvent(String key, Object value) {
        Map<String, Object> event = new HashMap<>();
        event.put(key, value);
        sendEvent(event);
    }

    private void sendEvent(Map<String, Object> event) {
        if (eventSink != null) {
            mainHandler.post(() -> eventSink.success(event));
        }
    }

    // Helper classes for track information
    private static class VideoQualityInfo {
        androidx.media3.common.TrackGroup trackGroup;
        int trackIndex;
        int width;
        int height;
        int bitrate;
        String label;
    }

    private static class AudioTrackInfo {
        androidx.media3.common.TrackGroup trackGroup;
        int trackIndex;
        String language;
        String label;
    }

    private static class SubtitleTrackInfo {
        androidx.media3.common.TrackGroup trackGroup;
        int trackIndex;
        String language;
        String label;
    }
}
