import 'dart:async';
import 'dart:developer';
import 'package:flutter/services.dart';
import '../models/video_track_models.dart';
import '../models/drm_config.dart';

/// Native video player service with multi-instance support
/// Each instance has a unique ID for channel communication
class NativeVideoPlayer {
  /// Shared method channel for all players
  static const MethodChannel _methodChannel = MethodChannel(
    'native_video_player/method',
  );

  /// Unique identifier for this player instance
  final String id;

  /// Event channel specific to this player
  late final EventChannel _eventChannel;

  // Private constructor for factory pattern
  NativeVideoPlayer._({required this.id}) {
    _eventChannel = EventChannel('native_video_player/event/$id');
  }

  /// Create a new player instance with optional ID
  static NativeVideoPlayer create({String? id}) {
    final playerId = id ?? _generateId();
    log('[NativeVideoPlayer] Creating instance: $playerId');
    return NativeVideoPlayer._(id: playerId);
  }

  static int _instanceCount = 0;

  /// Generate unique player ID
  static String _generateId() {
    _instanceCount++;
    return 'player_${DateTime.now().millisecondsSinceEpoch}_$_instanceCount';
  }

  // === Static Cache Management Methods ===

  /// Get current cache size in bytes
  static Future<int> getCacheSize() async {
    try {
      final size = await _methodChannel.invokeMethod('getCacheSize');
      return size as int;
    } catch (e) {
      return 0;
    }
  }

  /// Clear all cached video data
  static Future<void> clearCache() async {
    try {
      await _methodChannel.invokeMethod('clearCache');
      log('[NativeVideoPlayer] Cache cleared');
    } catch (e) {
      log('[NativeVideoPlayer] Failed to clear cache: $e');
    }
  }

  /// Check if caching is enabled
  static Future<bool> isCacheEnabled() async {
    try {
      final enabled = await _methodChannel.invokeMethod('isCacheEnabled');
      return enabled as bool;
    } catch (e) {
      return false;
    }
  }

  /// Prefetch video content without creating a player instance (headless)
  static Future<void> prefetchHeadless(String url) async {
    try {
      await _methodChannel.invokeMethod('prefetchHeadless', {'url': url});
    } catch (e) {
      log('[NativeVideoPlayer] Failed to prefetch headless: $e');
    }
  }

  // State
  int? _textureId;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isInitialized = false;
  bool _isDisposed = false;
  double _volume = 1.0;

  // Retry logic
  String? _currentUrl;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  bool _isRetrying = false;

  // Track caching
  bool _tracksLoaded = false;

  // Tracks
  List<VideoQuality> _availableQualities = [];
  List<AudioTrack> _availableAudioTracks = [];
  List<SubtitleTrack> _availableSubtitles = [];
  int _selectedQualityIndex = -1;
  int _selectedAudioIndex = -1;
  int _selectedSubtitleIndex = -1;
  bool _isAutoQuality = true;

  // Network state
  bool _isNetworkAvailable = true;
  String _networkType = 'unknown';

  // PiP state
  bool _isPiPActive = false;

  // Event subscription
  StreamSubscription? _eventSubscription;

  // Callbacks
  Function()? onInitialized;
  Function()? onTracksLoaded;
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
  Function(int attempt, int maxRetries)? onRetrying;
  Function(bool isConnected, String type)? onNetworkChanged;
  Function(bool isActive)? onPiPChanged;
  Function(double width, double height, double rotation)? onVideoSizeChanged;

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
  bool get isAutoQuality => _isAutoQuality;
  bool get isRetrying => _isRetrying;
  int get retryCount => _retryCount;
  bool get isNetworkAvailable => _isNetworkAvailable;
  String get networkType => _networkType;
  bool get isPiPActive => _isPiPActive;
  bool get isDisposed => _isDisposed;

  /// Helper to add player ID to method calls
  Map<String, dynamic> _withPlayerId(Map<String, dynamic> args) {
    return {'playerId': id, ...args};
  }

  /// Initialize the player with a video URL
  /// [drmConfig] - Optional DRM configuration for protected content
  Future<void> initialize(String url, {DrmConfig? drmConfig}) async {
    _currentUrl = url;
    _retryCount = 0;
    _tracksLoaded = false;

    try {
      final Map<String, dynamic> args = {'url': url};
      if (drmConfig != null) {
        args['drm'] = drmConfig.toMap();
      }

      final result = await _methodChannel.invokeMethod(
        'initialize',
        _withPlayerId(args),
      );

      _textureId = result['textureId'] as int;
      _isInitialized = true;
      _isRetrying = false;

      _startEventListener();
      await setVolume(_volume);

      log('[NativeVideoPlayer:$id] Initialized with texture: $_textureId');
      onInitialized?.call();
    } catch (e) {
      onError?.call('Failed to initialize: $e');
      await _attemptRetry();
    }
  }

  /// Preload video without playing (for feed scenarios)
  Future<void> preload(String url) async {
    _currentUrl = url;
    _tracksLoaded = false;

    try {
      final result = await _methodChannel.invokeMethod(
        'preload',
        _withPlayerId({'url': url}),
      );

      _textureId = result['textureId'] as int;
      _isInitialized = true;

      _startEventListener();
      log('[NativeVideoPlayer:$id] Preloaded: $url');
    } catch (e) {
      log('[NativeVideoPlayer:$id] Preload failed: $e');
      // Fallback to regular initialize if preload not supported
      await initialize(url);
    }
  }

  /// Attempt retry with exponential backoff
  Future<void> _attemptRetry() async {
    if (_currentUrl == null || _retryCount >= _maxRetries) {
      log('[NativeVideoPlayer:$id] Max retries reached');
      _isRetrying = false;
      return;
    }

    _retryCount++;
    _isRetrying = true;

    final delay = Duration(seconds: 1 << (_retryCount - 1));
    log(
      '[NativeVideoPlayer:$id] Retry $_retryCount/$_maxRetries in ${delay.inSeconds}s',
    );

    onRetrying?.call(_retryCount, _maxRetries);
    await Future.delayed(delay);

    if (_isRetrying && _currentUrl != null) {
      try {
        final result = await _methodChannel.invokeMethod(
          'initialize',
          _withPlayerId({'url': _currentUrl}),
        );

        _textureId = result['textureId'] as int;
        _isInitialized = true;
        _isRetrying = false;
        _retryCount = 0;

        _startEventListener();
        await setVolume(_volume);

        log('[NativeVideoPlayer:$id] Retry successful!');
        onInitialized?.call();
      } catch (e) {
        log('[NativeVideoPlayer:$id] Retry $_retryCount failed: $e');
        await _attemptRetry();
      }
    }
  }

  /// Manually retry connection
  Future<void> retryConnection() async {
    _retryCount = 0;
    if (_currentUrl != null) {
      await initialize(_currentUrl!);
    }
  }

  /// Play the video
  Future<void> play() async {
    try {
      await _methodChannel.invokeMethod('play', _withPlayerId({}));
    } catch (e) {
      onError?.call('Failed to play: $e');
    }
  }

  /// Pause the video
  Future<void> pause() async {
    try {
      await _methodChannel.invokeMethod('pause', _withPlayerId({}));
    } catch (e) {
      onError?.call('Failed to pause: $e');
    }
  }

  /// Seek to position
  Future<void> seekTo(Duration position) async {
    try {
      await _methodChannel.invokeMethod(
        'seekTo',
        _withPlayerId({'position': position.inMilliseconds}),
      );
    } catch (e) {
      onError?.call('Failed to seek: $e');
    }
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (!_isInitialized) return;

    try {
      await _methodChannel.invokeMethod(
        'setVolume',
        _withPlayerId({'volume': _volume}),
      );
    } catch (e) {
      onError?.call('Failed to set volume: $e');
    }
  }

  /// Set playback speed
  Future<void> setSpeed(double speed) async {
    try {
      await _methodChannel.invokeMethod(
        'setSpeed',
        _withPlayerId({'speed': speed}),
      );
    } catch (e) {
      onError?.call('Failed to set speed: $e');
    }
  }

  /// Get video duration
  Future<Duration> getDuration() async {
    try {
      final ms = await _methodChannel.invokeMethod(
        'getDuration',
        _withPlayerId({}),
      );
      return Duration(milliseconds: ms as int);
    } catch (e) {
      onError?.call('Failed to get duration: $e');
      return Duration.zero;
    }
  }

  /// Get current position
  Future<Duration> getCurrentPosition() async {
    try {
      final ms = await _methodChannel.invokeMethod(
        'getCurrentPosition',
        _withPlayerId({}),
      );
      return Duration(milliseconds: ms as int);
    } catch (e) {
      onError?.call('Failed to get position: $e');
      return Duration.zero;
    }
  }

  /// Get buffered position
  Future<Duration> getBufferedPosition() async {
    try {
      final ms = await _methodChannel.invokeMethod(
        'getBufferedPosition',
        _withPlayerId({}),
      );
      return Duration(milliseconds: ms as int);
    } catch (e) {
      onError?.call('Failed to get buffered position: $e');
      return Duration.zero;
    }
  }

  /// Get available qualities
  Future<List<VideoQuality>> getAvailableQualities() async {
    try {
      final result = await _methodChannel.invokeMethod(
        'getAvailableQualities',
        _withPlayerId({}),
      );
      final qualities =
          (result as List).map((q) => VideoQuality.fromMap(q as Map)).toList();
      _availableQualities = qualities;
      return qualities;
    } catch (e) {
      onError?.call('Failed to get qualities: $e');
      return [];
    }
  }

  /// Set quality index
  Future<void> setQuality(int index) async {
    try {
      await _methodChannel.invokeMethod(
        'setQuality',
        _withPlayerId({'index': index}),
      );
      _selectedQualityIndex = index;
      _isAutoQuality = false;
    } catch (e) {
      onError?.call('Failed to set quality: $e');
    }
  }

  /// Set auto quality (adaptive bitrate)
  Future<void> setAutoQuality() async {
    try {
      await _methodChannel.invokeMethod('setAutoQuality', _withPlayerId({}));
      _selectedQualityIndex = -1;
      _isAutoQuality = true;
    } catch (e) {
      onError?.call('Failed to set auto quality: $e');
    }
  }

  /// Get available audio tracks
  Future<List<AudioTrack>> getAvailableAudioTracks() async {
    try {
      final result = await _methodChannel.invokeMethod(
        'getAvailableAudioTracks',
        _withPlayerId({}),
      );
      final tracks =
          (result as List).map((a) => AudioTrack.fromMap(a as Map)).toList();
      _availableAudioTracks = tracks;
      return tracks;
    } catch (e) {
      onError?.call('Failed to get audio tracks: $e');
      return [];
    }
  }

  /// Set audio track
  Future<void> setAudioTrack(int index) async {
    try {
      await _methodChannel.invokeMethod(
        'setAudioTrack',
        _withPlayerId({'index': index}),
      );
      _selectedAudioIndex = index;
    } catch (e) {
      onError?.call('Failed to set audio track: $e');
    }
  }

  /// Get available subtitles
  Future<List<SubtitleTrack>> getAvailableSubtitles() async {
    try {
      final result = await _methodChannel.invokeMethod(
        'getAvailableSubtitles',
        _withPlayerId({}),
      );
      final subs =
          (result as List).map((s) => SubtitleTrack.fromMap(s as Map)).toList();
      _availableSubtitles = subs;
      return subs;
    } catch (e) {
      onError?.call('Failed to get subtitles: $e');
      return [];
    }
  }

  /// Set subtitle track (-1 to disable)
  Future<void> setSubtitle(int index) async {
    try {
      await _methodChannel.invokeMethod(
        'setSubtitle',
        _withPlayerId({'index': index}),
      );
      _selectedSubtitleIndex = index;
    } catch (e) {
      onError?.call('Failed to set subtitle: $e');
    }
  }

  /// Load external subtitle
  Future<void> loadExternalSubtitle(String url) async {
    try {
      await _methodChannel.invokeMethod(
        'loadExternalSubtitle',
        _withPlayerId({'url': url}),
      );
    } catch (e) {
      onError?.call('Failed to load external subtitle: $e');
    }
  }

  /// Enable offline mode
  Future<void> enableOfflineMode(String localPath) async {
    try {
      await _methodChannel.invokeMethod(
        'enableOfflineMode',
        _withPlayerId({'localPath': localPath}),
      );
    } catch (e) {
      onError?.call('Failed to enable offline mode: $e');
    }
  }

  /// Dispose player
  Future<void> dispose() async {
    if (_isDisposed) {
      log('[NativeVideoPlayer:$id] Already disposed, skipping');
      return;
    }

    _isDisposed = true;
    log('[NativeVideoPlayer:$id] Disposing...');

    _isRetrying = false;
    _currentUrl = null;

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    try {
      await _methodChannel.invokeMethod('dispose', _withPlayerId({}));
      log('[NativeVideoPlayer:$id] Disposed successfully');
    } catch (e) {
      log('[NativeVideoPlayer:$id] Error during disposal: $e');
    }

    _isInitialized = false;
    _textureId = null;
    _tracksLoaded = false;
  }

  /// Load all tracks
  Future<void> loadTracks({bool forceRefresh = false}) async {
    if (_tracksLoaded && !forceRefresh) {
      return;
    }

    await getAvailableQualities();
    await getAvailableAudioTracks();
    await getAvailableSubtitles();

    if (_availableQualities.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
      await getAvailableQualities();
      await getAvailableAudioTracks();
      await getAvailableSubtitles();
    }

    if (_availableQualities.isNotEmpty || _availableAudioTracks.isNotEmpty) {
      _tracksLoaded = true;
    }
    onTracksLoaded?.call();
  }

  /// Enter Picture-in-Picture
  Future<bool> enterPiP() async {
    try {
      final result = await _methodChannel.invokeMethod(
        'enterPiP',
        _withPlayerId({}),
      );
      return result == true;
    } catch (e) {
      onError?.call('PiP not available: $e');
      return false;
    }
  }

  /// Get network status
  Future<Map<String, dynamic>> getNetworkStatus() async {
    try {
      final result = await _methodChannel.invokeMethod(
        'getNetworkStatus',
        _withPlayerId({}),
      );
      _isNetworkAvailable = result['isConnected'] as bool;
      _networkType = result['type'] as String;
      return {'isConnected': _isNetworkAvailable, 'type': _networkType};
    } catch (e) {
      return {'isConnected': true, 'type': 'unknown'};
    }
  }

  /// Start event listener
  void _startEventListener() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
          (event) => _handleEvent(event as Map),
          onError: (error) => onError?.call('Event error: $error'),
        );
  }

  /// Handle events
  void _handleEvent(Map<dynamic, dynamic> event) {
    final eventType = event['event'] as String?;

    if (eventType == 'position') {
      _position = Duration(milliseconds: event['position'] as int);
      _bufferedPosition = Duration(
        milliseconds: event['bufferedPosition'] as int,
      );
      _duration = Duration(milliseconds: event['duration'] as int);
      onPositionUpdate?.call(_position, _bufferedPosition, _duration);
    } else if (event.containsKey('playbackState')) {
      final state = event['playbackState'] as String;
      if (state == 'playing') {
        _isPlaying = true;
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
      _isBuffering = event['bufferState'] == 'buffering';
      onBufferingStateChanged?.call(_isBuffering);
    } else if (eventType == 'error') {
      onError?.call(event['message'] as String);
    } else if (eventType == 'qualityChanged') {
      _selectedQualityIndex = event['index'] as int;
      _isAutoQuality = (event['isAuto'] as bool?) ?? false;
      loadTracks();
      onQualityChanged?.call(_selectedQualityIndex);
    } else if (eventType == 'audioChanged') {
      _selectedAudioIndex = event['index'] as int;
      loadTracks();
      onAudioChanged?.call(_selectedAudioIndex);
    } else if (eventType == 'subtitleChanged') {
      _selectedSubtitleIndex = event['index'] as int;
      loadTracks();
      onSubtitleChanged?.call(_selectedSubtitleIndex);
    } else if (eventType == 'subtitleText') {
      onSubtitleText?.call(event['text'] as String);
    } else if (eventType == 'networkChanged') {
      _isNetworkAvailable = event['isConnected'] as bool;
      _networkType = event['type'] as String;
      onNetworkChanged?.call(_isNetworkAvailable, _networkType);
    } else if (eventType == 'pipChanged') {
      _isPiPActive = event['isActive'] as bool;
      onPiPChanged?.call(_isPiPActive);
    } else if (eventType == 'videoSize') {
      final width = (event['width'] as num).toDouble();
      final height = (event['height'] as num).toDouble();
      final rotation = (event['rotation'] as num?)?.toDouble() ?? 0.0;
      onVideoSizeChanged?.call(width, height, rotation);
    }
  }
}
