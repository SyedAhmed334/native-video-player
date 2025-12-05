import 'dart:async';
import 'dart:developer';
import 'package:flutter/services.dart';
import '../models/video_track_models.dart';

/// Native video player controller
/// Manages communication with the native ExoPlayer implementation
class NativeVideoPlayer {
  static const MethodChannel _methodChannel = MethodChannel(
    'native_video_player/method',
  );
  static const EventChannel _eventChannel = EventChannel(
    'native_video_player/event',
  );

  // State
  int? _textureId;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isInitialized = false;
  double _volume = 1.0; // Default volume

  // Tracks
  List<VideoQuality> _availableQualities = [];
  List<AudioTrack> _availableAudioTracks = [];
  List<SubtitleTrack> _availableSubtitles = [];
  int _selectedQualityIndex = -1;
  int _selectedAudioIndex = -1;
  int _selectedSubtitleIndex = -1;

  // Event subscription
  StreamSubscription? _eventSubscription;

  // Callbacks
  Function()? onInitialized;
  Function(Duration position, Duration bufferedPosition, Duration duration)?
  onPositionUpdate;
  Function(bool isPlaying)? onPlaybackStateChanged;
  Function(bool isBuffering)? onBufferingStateChanged;
  Function()? onCompleted;
  Function(String message)? onError;
  Function(int index)? onQualityChanged;
  Function(int index)? onAudioChanged;
  Function(int index)? onSubtitleChanged;
  Function(String text)? onSubtitleText;

  // Getters
  int? get textureId => _textureId;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get isInitialized => _isInitialized;
  double get volume => _volume;
  List<VideoQuality> get availableQualities => _availableQualities;
  List<AudioTrack> get availableAudioTracks => _availableAudioTracks;
  List<SubtitleTrack> get availableSubtitles => _availableSubtitles;
  int get selectedQualityIndex => _selectedQualityIndex;
  int get selectedAudioIndex => _selectedAudioIndex;
  int get selectedSubtitleIndex => _selectedSubtitleIndex;

  /// Initialize the player with a video URL
  /// Supports HLS (.m3u8), DASH (.mpd), and MP4 formats
  Future<void> initialize(String url) async {
    try {
      final result = await _methodChannel.invokeMethod('initialize', {
        'url': url,
      });

      _textureId = result['textureId'] as int;
      _isInitialized = true;

      // Start listening to events
      _startEventListener();

      // Set volume to 1.0 (full volume) by default
      await setVolume(1.0);

      // Don't load tracks here - they're not ready yet
      // Tracks will be loaded when playback starts (after onTracksChanged)

      onInitialized?.call();
    } catch (e) {
      onError?.call('Failed to initialize: $e');
      rethrow;
    }
  }

  /// Play the video
  Future<void> play() async {
    try {
      await _methodChannel.invokeMethod('play');
    } catch (e) {
      onError?.call('Failed to play: $e');
    }
  }

  /// Pause the video
  Future<void> pause() async {
    try {
      await _methodChannel.invokeMethod('pause');
    } catch (e) {
      onError?.call('Failed to pause: $e');
    }
  }

  /// Seek to a specific position
  Future<void> seekTo(Duration position) async {
    try {
      await _methodChannel.invokeMethod('seekTo', {
        'position': position.inMilliseconds,
      });
    } catch (e) {
      onError?.call('Failed to seek: $e');
    }
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    try {
      await _methodChannel.invokeMethod('setVolume', {
        'volume': volume.clamp(0.0, 1.0),
      });
      _volume = volume.clamp(0.0, 1.0);
    } catch (e) {
      onError?.call('Failed to set volume: $e');
    }
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    try {
      await _methodChannel.invokeMethod('setSpeed', {'speed': speed});
    } catch (e) {
      onError?.call('Failed to set speed: $e');
    }
  }

  /// Get video duration
  Future<Duration> getDuration() async {
    try {
      final milliseconds = await _methodChannel.invokeMethod('getDuration');
      return Duration(milliseconds: milliseconds as int);
    } catch (e) {
      onError?.call('Failed to get duration: $e');
      return Duration.zero;
    }
  }

  /// Get current position
  Future<Duration> getCurrentPosition() async {
    try {
      final milliseconds = await _methodChannel.invokeMethod(
        'getCurrentPosition',
      );
      return Duration(milliseconds: milliseconds as int);
    } catch (e) {
      onError?.call('Failed to get position: $e');
      return Duration.zero;
    }
  }

  /// Get buffered position
  Future<Duration> getBufferedPosition() async {
    try {
      final milliseconds = await _methodChannel.invokeMethod(
        'getBufferedPosition',
      );
      return Duration(milliseconds: milliseconds as int);
    } catch (e) {
      onError?.call('Failed to get buffered position: $e');
      return Duration.zero;
    }
  }

  /// Get available video quality tracks
  Future<List<VideoQuality>> getAvailableQualities() async {
    try {
      final result = await _methodChannel.invokeMethod('getAvailableQualities');
      log("[NativePlayer][Qualities] $result");
      final qualities = (result as List)
          .map((q) => VideoQuality.fromMap(q as Map))
          .toList();
      _availableQualities = qualities;
      return qualities;
    } catch (e) {
      onError?.call('Failed to get qualities: $e');
      return [];
    }
  }

  /// Set video quality - SEAMLESS SWITCHING
  /// No pause, no reload, Netflix-smooth
  Future<void> setQuality(int index) async {
    try {
      await _methodChannel.invokeMethod('setQuality', {'index': index});
      _selectedQualityIndex = index;
    } catch (e) {
      onError?.call('Failed to set quality: $e');
    }
  }

  /// Get available audio tracks
  Future<List<AudioTrack>> getAvailableAudioTracks() async {
    try {
      final result = await _methodChannel.invokeMethod(
        'getAvailableAudioTracks',
      );
      log("[NativePlayer][AudioTracks] $result");

      final audioTracks = (result as List)
          .map((a) => AudioTrack.fromMap(a as Map))
          .toList();
      _availableAudioTracks = audioTracks;
      return audioTracks;
    } catch (e) {
      onError?.call('Failed to get audio tracks: $e');
      return [];
    }
  }

  /// Set audio track - INSTANT SWITCHING
  /// No reload, immediate change
  Future<void> setAudioTrack(int index) async {
    try {
      await _methodChannel.invokeMethod('setAudioTrack', {'index': index});
      _selectedAudioIndex = index;
    } catch (e) {
      onError?.call('Failed to set audio track: $e');
    }
  }

  /// Get available subtitle tracks
  Future<List<SubtitleTrack>> getAvailableSubtitles() async {
    try {
      final result = await _methodChannel.invokeMethod('getAvailableSubtitles');
      log("[NativePlayer][Subtitles] $result");

      final subtitles = (result as List)
          .map((s) => SubtitleTrack.fromMap(s as Map))
          .toList();
      _availableSubtitles = subtitles;
      return subtitles;
    } catch (e) {
      onError?.call('Failed to get subtitles: $e');
      return [];
    }
  }

  /// Set subtitle track - INSTANT SWITCHING
  /// Pass -1 to disable subtitles
  Future<void> setSubtitle(int index) async {
    try {
      await _methodChannel.invokeMethod('setSubtitle', {'index': index});
      _selectedSubtitleIndex = index;
    } catch (e) {
      onError?.call('Failed to set subtitle: $e');
    }
  }

  /// Load external subtitle file (.vtt or .srt)
  Future<void> loadExternalSubtitle(String url) async {
    try {
      await _methodChannel.invokeMethod('loadExternalSubtitle', {'url': url});
    } catch (e) {
      onError?.call('Failed to load external subtitle: $e');
    }
  }

  /// Enable offline playback mode
  /// Use local file path
  Future<void> enableOfflineMode(String localPath) async {
    try {
      await _methodChannel.invokeMethod('enableOfflineMode', {
        'localPath': localPath,
      });
    } catch (e) {
      onError?.call('Failed to enable offline mode: $e');
    }
  }

  /// Dispose the player and release resources
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    try {
      await _methodChannel.invokeMethod('dispose');
    } catch (e) {
      // Ignore errors during disposal
    }

    _isInitialized = false;
    _textureId = null;
  }

  /// Load all available tracks
  /// Retries with delay to ensure media is prepared
  Future<void> loadTracks() async {
    // Initial load (will be empty if tracks not ready yet)
    await getAvailableQualities();
    await getAvailableAudioTracks();
    await getAvailableSubtitles();

    // ALWAYS retry after 500ms (tracks become available after onTracksChanged)
    await Future.delayed(const Duration(milliseconds: 500));
    await getAvailableQualities();
    await getAvailableAudioTracks();
    await getAvailableSubtitles();

    // ALWAYS retry again after another 500ms for slow connections
    await Future.delayed(const Duration(milliseconds: 500));
    await getAvailableQualities();
    await getAvailableAudioTracks();
    await getAvailableSubtitles();
  }

  /// Start listening to player events
  void _startEventListener() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        _handleEvent(event as Map);
      },
      onError: (error) {
        onError?.call('Event error: $error');
      },
    );
  }

  /// Handle events from native player
  void _handleEvent(Map<dynamic, dynamic> event) {
    final eventType = event['event'] as String?;

    if (eventType == 'position') {
      // Position update
      _position = Duration(milliseconds: event['position'] as int);
      _bufferedPosition = Duration(
        milliseconds: event['bufferedPosition'] as int,
      );
      _duration = Duration(milliseconds: event['duration'] as int);
      onPositionUpdate?.call(_position, _bufferedPosition, _duration);
    } else if (event.containsKey('playbackState')) {
      // Playback state change
      final state = event['playbackState'] as String;
      if (state == 'playing') {
        _isPlaying = true;
        // Load tracks when playback starts (tracks are ready by now)
        loadTracks();
        onPlaybackStateChanged?.call(true);
      } else if (state == 'paused') {
        _isPlaying = false;
        onPlaybackStateChanged?.call(false);
      } else if (state == 'completed') {
        _isPlaying = false;
        onCompleted?.call();
      }
    } else if (event.containsKey('bufferState')) {
      // Buffer state change
      final state = event['bufferState'] as String;
      _isBuffering = state == 'buffering';
      onBufferingStateChanged?.call(_isBuffering);
    } else if (eventType == 'error') {
      // Error
      onError?.call(event['message'] as String);
    } else if (eventType == 'qualityChanged') {
      // Quality changed
      _selectedQualityIndex = event['index'] as int;
      // Reload tracks to ensure we have latest info
      loadTracks();
      onQualityChanged?.call(_selectedQualityIndex);
    } else if (eventType == 'audioChanged') {
      // Audio track changed
      _selectedAudioIndex = event['index'] as int;
      // Reload tracks to ensure we have latest info
      loadTracks();
      onAudioChanged?.call(_selectedAudioIndex);
    } else if (eventType == 'subtitleChanged') {
      // Subtitle changed
      _selectedSubtitleIndex = event['index'] as int;
      // Reload tracks to ensure we have latest info
      loadTracks();
      onSubtitleChanged?.call(_selectedSubtitleIndex);
    } else if (eventType == 'subtitleText') {
      // Subtitle text update
      onSubtitleText?.call(event['text'] as String);
    }
  }
}
