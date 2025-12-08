/// Analytics event types for video player
enum AnalyticsEventType {
  /// Video started playing
  play,

  /// Video paused
  pause,

  /// User seeked to a position
  seek,

  /// Video playback completed
  complete,

  /// Buffering started
  bufferStart,

  /// Buffering ended
  bufferEnd,

  /// Quality changed (manual or auto)
  qualityChange,

  /// Audio track changed
  audioTrackChange,

  /// Subtitle changed
  subtitleChange,

  /// Error occurred
  error,

  /// Player initialized
  initialized,

  /// Player disposed
  disposed,

  /// First frame rendered
  firstFrame,

  /// User entered fullscreen
  enterFullscreen,

  /// User exited fullscreen
  exitFullscreen,

  /// Picture-in-Picture entered
  enterPiP,

  /// Picture-in-Picture exited
  exitPiP,
}

/// Analytics event with metadata
class VideoAnalyticsEvent {
  /// Type of the event
  final AnalyticsEventType type;

  /// Timestamp when event occurred
  final DateTime timestamp;

  /// Current playback position when event occurred
  final Duration position;

  /// Total video duration (if available)
  final Duration? duration;

  /// Additional event-specific data
  final Map<String, dynamic> metadata;

  const VideoAnalyticsEvent({
    required this.type,
    required this.timestamp,
    required this.position,
    this.duration,
    this.metadata = const {},
  });

  /// Create event for current time
  factory VideoAnalyticsEvent.now({
    required AnalyticsEventType type,
    required Duration position,
    Duration? duration,
    Map<String, dynamic> metadata = const {},
  }) {
    return VideoAnalyticsEvent(
      type: type,
      timestamp: DateTime.now(),
      position: position,
      duration: duration,
      metadata: metadata,
    );
  }

  /// Convert to Map for JSON serialization
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'positionMs': position.inMilliseconds,
      'durationMs': duration?.inMilliseconds,
      ...metadata,
    };
  }

  @override
  String toString() {
    return 'VideoAnalyticsEvent(${type.name} at ${position.inSeconds}s)';
  }
}

/// Callback type for analytics events
typedef VideoAnalyticsCallback = void Function(VideoAnalyticsEvent event);

/// Analytics configuration
class AnalyticsConfig {
  /// Whether to track play/pause events
  final bool trackPlayback;

  /// Whether to track seek events
  final bool trackSeek;

  /// Whether to track quality changes
  final bool trackQuality;

  /// Whether to track errors
  final bool trackErrors;

  /// Whether to track buffering events
  final bool trackBuffering;

  /// Minimum seek distance to trigger event (prevents micro-seeks)
  final Duration seekThreshold;

  const AnalyticsConfig({
    this.trackPlayback = true,
    this.trackSeek = true,
    this.trackQuality = true,
    this.trackErrors = true,
    this.trackBuffering = true,
    this.seekThreshold = const Duration(seconds: 2),
  });

  /// Track all events
  static const all = AnalyticsConfig();

  /// Track only essential events (play, pause, complete, error)
  static const essential = AnalyticsConfig(
    trackSeek: false,
    trackQuality: false,
    trackBuffering: false,
  );

  /// Minimal tracking (errors only)
  static const errorsOnly = AnalyticsConfig(
    trackPlayback: false,
    trackSeek: false,
    trackQuality: false,
    trackBuffering: false,
  );
}
