// Unused import removed - VideoPlayerConfig doesn't need material

/// Configuration options for the video player
class VideoPlayerConfig {
  /// Auto-start playback when initialized
  final bool autoPlay;

  /// Loop video when finished
  final bool loop;

  /// Start muted
  final bool muted;

  /// Initial volume (0.0 to 1.0)
  final double volume;

  /// Duration for seek operations (rewind/forward)
  final Duration seekDuration;

  /// Duration before controls auto-hide
  final Duration controlsAutoHideDuration;

  /// Show overlay controls
  final bool showControls;

  /// Enable double-tap to seek
  final bool enableDoubleTapSeek;

  /// Enable segment caching for smoother playback
  final bool enableCaching;

  /// Maximum cache size in MB (null = default 100MB)
  final int? cacheMaxSizeMB;

  /// Maximum number of simultaneous player instances
  final int maxPlayerInstances;

  const VideoPlayerConfig({
    this.autoPlay = true,
    this.loop = false,
    this.muted = false,
    this.volume = 1.0,
    this.seekDuration = const Duration(seconds: 10),
    this.controlsAutoHideDuration = const Duration(seconds: 3),
    this.showControls = true,
    this.enableDoubleTapSeek = true,
    this.enableCaching = false,
    this.cacheMaxSizeMB,
    this.maxPlayerInstances = 3,
  });

  /// Create a copy with modified values
  VideoPlayerConfig copyWith({
    bool? autoPlay,
    bool? loop,
    bool? muted,
    double? volume,
    Duration? seekDuration,
    Duration? controlsAutoHideDuration,
    bool? showControls,
    bool? enableDoubleTapSeek,
    bool? enableCaching,
    int? cacheMaxSizeMB,
    int? maxPlayerInstances,
  }) {
    return VideoPlayerConfig(
      autoPlay: autoPlay ?? this.autoPlay,
      loop: loop ?? this.loop,
      muted: muted ?? this.muted,
      volume: volume ?? this.volume,
      seekDuration: seekDuration ?? this.seekDuration,
      controlsAutoHideDuration:
          controlsAutoHideDuration ?? this.controlsAutoHideDuration,
      showControls: showControls ?? this.showControls,
      enableDoubleTapSeek: enableDoubleTapSeek ?? this.enableDoubleTapSeek,
      enableCaching: enableCaching ?? this.enableCaching,
      cacheMaxSizeMB: cacheMaxSizeMB ?? this.cacheMaxSizeMB,
      maxPlayerInstances: maxPlayerInstances ?? this.maxPlayerInstances,
    );
  }

  /// Default configuration for single-video playback
  static const standard = VideoPlayerConfig();

  /// Configuration optimized for feed/TikTok-style playback
  static const feed = VideoPlayerConfig(
    autoPlay: true,
    loop: true,
    showControls: false,
    enableDoubleTapSeek: false,
    enableCaching: true,
    maxPlayerInstances: 3,
  );
}
