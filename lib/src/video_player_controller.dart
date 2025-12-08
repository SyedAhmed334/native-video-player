import 'dart:developer';

import 'package:flutter/material.dart';
import 'services/native_video_player_service.dart';
import 'models/video_track_models.dart';
import 'models/analytics_event.dart';
import 'models/playback_error.dart';

/// Controller for the Custom Video Player
/// Manages all video player state with ValueNotifiers
class VideoPlayerController {
  final String url;
  final bool autoPlay;
  final String? playerId;

  /// Analytics configuration
  final AnalyticsConfig analyticsConfig;

  VideoPlayerController({
    required this.url,
    this.autoPlay = true,
    this.playerId,
    this.analyticsConfig = const AnalyticsConfig(),
  });

  // Native player instance
  late NativeVideoPlayer _nativePlayer;
  NativeVideoPlayer get nativePlayer => _nativePlayer;

  // Reactive state variables
  final isInitialized = ValueNotifier<bool>(false);
  final initialIndexAssigned = ValueNotifier<bool>(false);
  final isLoading = ValueNotifier<bool>(true);
  final isPlaying = ValueNotifier<bool>(false);
  final isBuffering = ValueNotifier<bool>(false);
  final showControls = ValueNotifier<bool>(true);
  final subtitleText = ValueNotifier<String>('');

  // Position and duration
  final position = ValueNotifier<Duration>(Duration.zero);
  final bufferedPosition = ValueNotifier<Duration>(Duration.zero);
  final duration = ValueNotifier<Duration>(Duration.zero);

  // Track lists
  final availableQualities = ValueNotifier<List<VideoQuality>>([]);
  final availableAudioTracks = ValueNotifier<List<AudioTrack>>([]);
  final availableSubtitles = ValueNotifier<List<SubtitleTrack>>([]);

  // Selected track indices
  final selectedQualityIndex = ValueNotifier<int>(-1);
  final selectedAudioIndex = ValueNotifier<int>(-1);
  final selectedSubtitleIndex = ValueNotifier<int>(-1);

  // Volume
  final volume = ValueNotifier<double>(1.0);

  // Auto quality mode
  final isAutoQuality = ValueNotifier<bool>(true);

  // Seeking state (prevents position updates during slider drag)
  final isSeeking = ValueNotifier<bool>(false);

  // Retry state
  final isRetrying = ValueNotifier<bool>(false);
  final retryCount = ValueNotifier<int>(0);

  // Texture ID
  final textureId = ValueNotifier<int?>(null);

  // Double-tap seek state
  final isDoubleTapSeekingForward = ValueNotifier<bool>(false);
  final isDoubleTapSeekingBackward = ValueNotifier<bool>(false);
  final doubleTapSeekSeconds = ValueNotifier<int>(0);
  final doubleTapAnimationKey = ValueNotifier<int>(0);

  // Network state
  final isNetworkConnected = ValueNotifier<bool>(true);
  final networkType = ValueNotifier<String>('unknown');

  // Picture-in-Picture state
  final isPiPActive = ValueNotifier<bool>(false);

  // Error recovery state
  final lastError = ValueNotifier<PlaybackError?>(null);
  final hasError = ValueNotifier<bool>(false);

  // Buffer health (0.0 to 1.0)
  final bufferHealth = ValueNotifier<double>(1.0);
  final isBufferLow = ValueNotifier<bool>(false);

  /// Clear current error and retry playback
  void clearError() {
    lastError.value = null;
    hasError.value = false;
  }

  /// Set error from native error message
  void _setError(String message) {
    final error = PlaybackError.fromNative(message);
    lastError.value = error;
    hasError.value = true;
    _emitAnalytics(AnalyticsEventType.error, metadata: error.toMap());
  }

  /// Update buffer health based on buffered vs total duration
  void _updateBufferHealth() {
    final buffered = bufferedPosition.value.inMilliseconds;
    final pos = position.value.inMilliseconds;
    final dur = duration.value.inMilliseconds;

    if (dur > 0) {
      // Buffer health = how much is buffered ahead relative to remaining
      final remaining = dur - pos;
      final bufferedAhead = buffered - pos;

      if (remaining > 0) {
        bufferHealth.value = (bufferedAhead / remaining).clamp(0.0, 1.0);
        isBufferLow.value = bufferHealth.value < 0.1; // Less than 10% buffered
      } else {
        bufferHealth.value = 1.0;
        isBufferLow.value = false;
      }
    }
  }

  // Callbacks for UI interaction
  Function(String message)? onError;
  Function(bool isConnected, String type)? onNetworkChanged;

  /// Analytics event callback
  VideoAnalyticsCallback? onAnalyticsEvent;

  /// Emit an analytics event
  void _emitAnalytics(
    AnalyticsEventType type, {
    Map<String, dynamic> metadata = const {},
  }) {
    if (onAnalyticsEvent == null) return;

    // Check config to see if this event type should be tracked
    switch (type) {
      case AnalyticsEventType.play:
      case AnalyticsEventType.pause:
      case AnalyticsEventType.complete:
        if (!analyticsConfig.trackPlayback) return;
        break;
      case AnalyticsEventType.seek:
        if (!analyticsConfig.trackSeek) return;
        break;
      case AnalyticsEventType.qualityChange:
      case AnalyticsEventType.audioTrackChange:
      case AnalyticsEventType.subtitleChange:
        if (!analyticsConfig.trackQuality) return;
        break;
      case AnalyticsEventType.error:
        if (!analyticsConfig.trackErrors) return;
        break;
      case AnalyticsEventType.bufferStart:
      case AnalyticsEventType.bufferEnd:
        if (!analyticsConfig.trackBuffering) return;
        break;
      default:
        break;
    }

    final event = VideoAnalyticsEvent.now(
      type: type,
      position: position.value,
      duration: duration.value,
      metadata: metadata,
    );

    onAnalyticsEvent!(event);
    log('[Analytics] ${event.type.name} at ${event.position.inSeconds}s');
  }

  void initialize() {
    // Defer player initialization to after the navigation animation completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayer();
    });
  }

  void dispose() {
    _nativePlayer.dispose();
    isInitialized.dispose();
    initialIndexAssigned.dispose();
    isLoading.dispose();
    isPlaying.dispose();
    isBuffering.dispose();
    showControls.dispose();
    subtitleText.dispose();
    position.dispose();
    bufferedPosition.dispose();
    duration.dispose();
    availableQualities.dispose();
    availableAudioTracks.dispose();
    availableSubtitles.dispose();
    selectedQualityIndex.dispose();
    selectedAudioIndex.dispose();
    selectedSubtitleIndex.dispose();
    volume.dispose();
    isAutoQuality.dispose();
    isSeeking.dispose();
    isRetrying.dispose();
    retryCount.dispose();
    textureId.dispose();
    isDoubleTapSeekingForward.dispose();
    isDoubleTapSeekingBackward.dispose();
    doubleTapSeekSeconds.dispose();
    doubleTapAnimationKey.dispose();
    isNetworkConnected.dispose();
    networkType.dispose();
    isPiPActive.dispose();
  }

  /// Initialize the native video player
  Future<void> _initializePlayer() async {
    // Ensure loading state is set before starting initialization
    isLoading.value = true;

    // Create player with unique ID for multi-instance support
    _nativePlayer = NativeVideoPlayer.create(id: playerId);

    // Set up callbacks
    _nativePlayer.onInitialized = () {
      textureId.value = _nativePlayer.textureId;
      isInitialized.value = true;
      isRetrying.value = false;
      retryCount.value = 0;
      if (autoPlay) {
        _nativePlayer.play();
      }
    };

    _nativePlayer.onPositionUpdate = (pos, buffered, dur) {
      // Don't update position while user is dragging the slider
      if (!isSeeking.value) {
        position.value = pos;
      }
      bufferedPosition.value = buffered;
      duration.value = dur;
      _updateBufferHealth();
    };

    _nativePlayer.onTracksLoaded = () {
      _syncTracks();
    };

    _nativePlayer.onPlaybackStateChanged = (playing) {
      log("Now Playing...");
      isPlaying.value = playing;
    };

    _nativePlayer.onBufferingStateChanged = (buffering) {
      isBuffering.value = buffering;
      isLoading.value = buffering;
    };

    _nativePlayer.onSubtitleText = (text) {
      subtitleText.value = text;
    };

    _nativePlayer.onError = (message) {
      log("[Player Error] $message");
      _setError(message);
      onError?.call(message);
    };

    _nativePlayer.onQualityChanged = (index) {
      selectedQualityIndex.value = index;
      _syncTracks();
    };

    _nativePlayer.onAudioChanged = (index) {
      selectedAudioIndex.value = index;
      _syncTracks();
    };

    _nativePlayer.onSubtitleChanged = (index) {
      selectedSubtitleIndex.value = index;
      _syncTracks();
    };

    _nativePlayer.onRetrying = (attempt, maxRetries) {
      isRetrying.value = true;
      retryCount.value = attempt;
      log('[Player] Retrying connection: attempt $attempt/$maxRetries');
    };

    _nativePlayer.onNetworkChanged = (isConnected, type) {
      isNetworkConnected.value = isConnected;
      networkType.value = type;
      log('[Player] Network changed: $type (connected: $isConnected)');
      onNetworkChanged?.call(isConnected, type);
    };

    _nativePlayer.onPiPChanged = (isActive) {
      isPiPActive.value = isActive;
      log('[Player] PiP mode: $isActive');

      if (isActive) {
        // Hide controls when in PiP
        showControls.value = false;

        // Resume playback if it was paused by lifecycle handler
        // (The lifecycle handler fires before PiP event arrives)
        Future.delayed(const Duration(milliseconds: 100), () {
          if (isPiPActive.value && !isPlaying.value) {
            log('[Player] Resuming playback in PiP mode');
            play();
          }
        });
      }
    };

    // Initialize with URL
    await _nativePlayer.initialize(url);
  }

  /// Sync track lists from native player
  void _syncTracks() {
    final qualities = List<VideoQuality>.from(_nativePlayer.availableQualities);
    qualities.sort((a, b) {
      // First sort by height
      int heightCompare = b.height.compareTo(a.height);
      if (heightCompare != 0) return heightCompare;

      // If equal, sort by width
      int widthCompare = b.width.compareTo(a.width);
      if (widthCompare != 0) return widthCompare;

      // If still equal, sort by bitrate
      return b.bitrate.compareTo(a.bitrate);
    });
    availableQualities.value = qualities;

    availableAudioTracks.value = _nativePlayer.availableAudioTracks
        .where(
          (track) => track.language != 'Unknown' && track.label != 'Unknown',
        )
        .toList();

    availableSubtitles.value = _nativePlayer.availableSubtitles
        .where(
          (track) => track.language != 'Unknown' && track.label != 'Unknown',
        )
        .toList();

    selectedQualityIndex.value = _nativePlayer.selectedQualityIndex;
    selectedAudioIndex.value = _nativePlayer.selectedAudioIndex;
    selectedSubtitleIndex.value = _nativePlayer.selectedSubtitleIndex;
    volume.value = _nativePlayer.volume;
    isAutoQuality.value = _nativePlayer.isAutoQuality;

    if (availableAudioTracks.value.isNotEmpty && !initialIndexAssigned.value) {
      selectedAudioIndex.value = 0;
      initialIndexAssigned.value = true;
    }
  }

  /// Toggle controls visibility
  void toggleControls() {
    showControls.value = !showControls.value;
  }

  /// Play video
  void play() {
    _nativePlayer.play();
    _emitAnalytics(AnalyticsEventType.play);
  }

  /// Pause video
  void pause() {
    _nativePlayer.pause();
    _emitAnalytics(AnalyticsEventType.pause);
  }

  /// Toggle play/pause
  void togglePlayPause() {
    if (isPlaying.value) {
      pause();
    } else {
      play();
    }
  }

  /// Seek to a specific position
  void seekTo(Duration pos) {
    final oldPosition = position.value;
    _nativePlayer.seekTo(pos);
    _emitAnalytics(
      AnalyticsEventType.seek,
      metadata: {
        'fromMs': oldPosition.inMilliseconds,
        'toMs': pos.inMilliseconds,
      },
    );
  }

  /// Rewind by specified seconds
  void rewind({int seconds = 10}) {
    final newPosition = position.value - Duration(seconds: seconds);
    seekTo(newPosition.isNegative ? Duration.zero : newPosition);
  }

  /// Forward by specified seconds
  void forward({int seconds = 10}) {
    final newPosition = position.value + Duration(seconds: seconds);
    seekTo(newPosition > duration.value ? duration.value : newPosition);
  }

  /// Handle double-tap to seek forward
  void doubleTapSeekForward({int seconds = 10}) {
    // Reset backward if it was active
    if (isDoubleTapSeekingBackward.value) {
      isDoubleTapSeekingBackward.value = false;
      doubleTapSeekSeconds.value = 0;
    }

    // Accumulate seek time for rapid taps
    doubleTapSeekSeconds.value += seconds;
    isDoubleTapSeekingForward.value = true;
    doubleTapAnimationKey.value++;

    // Perform the seek
    forward(seconds: seconds);

    // Reset after animation
    Future.delayed(const Duration(milliseconds: 800), () {
      if (isDoubleTapSeekingForward.value) {
        isDoubleTapSeekingForward.value = false;
        doubleTapSeekSeconds.value = 0;
      }
    });
  }

  /// Handle double-tap to seek backward
  void doubleTapSeekBackward({int seconds = 10}) {
    // Reset forward if it was active
    if (isDoubleTapSeekingForward.value) {
      isDoubleTapSeekingForward.value = false;
      doubleTapSeekSeconds.value = 0;
    }

    // Accumulate seek time for rapid taps
    doubleTapSeekSeconds.value += seconds;
    isDoubleTapSeekingBackward.value = true;
    doubleTapAnimationKey.value++;

    // Perform the seek
    rewind(seconds: seconds);

    // Reset after animation
    Future.delayed(const Duration(milliseconds: 800), () {
      if (isDoubleTapSeekingBackward.value) {
        isDoubleTapSeekingBackward.value = false;
        doubleTapSeekSeconds.value = 0;
      }
    });
  }

  /// Set volume (0.0 to 1.0)
  void setVolume(double vol) {
    _nativePlayer.setVolume(vol);
    volume.value = vol;
  }

  /// Set playback speed
  void setSpeed(double speed) {
    _nativePlayer.setSpeed(speed);
  }

  /// Set video quality
  void setQuality(int index, BuildContext context) {
    _nativePlayer.setQuality(index);
    isAutoQuality.value = false;
    _emitAnalytics(
      AnalyticsEventType.qualityChange,
      metadata: {'index': index},
    );
    Navigator.of(context).pop();
  }

  /// Set auto quality (adaptive bitrate)
  void setAutoQuality(BuildContext context) {
    _nativePlayer.setAutoQuality();
    isAutoQuality.value = true;
    Navigator.of(context).pop();
  }

  /// Enter Picture-in-Picture mode
  Future<void> enterPiP(BuildContext context) async {
    await _nativePlayer.enterPiP();
  }

  /// Set audio track
  void setAudioTrack(int index, BuildContext context) {
    _nativePlayer.setAudioTrack(index);
    _emitAnalytics(
      AnalyticsEventType.audioTrackChange,
      metadata: {'index': index},
    );
    Navigator.of(context).pop();
  }

  /// Set subtitle track (-1 to disable)
  void setSubtitle(int index, BuildContext context) {
    _nativePlayer.setSubtitle(index);
    Navigator.of(context).pop();
  }

  /// Retry connection after failure
  void retryConnection() {
    _nativePlayer.retryConnection();
  }

  /// Show quality selector bottom sheet
  void showQualitySelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD000000),
      builder: (_) => _buildQualitySelectorSheet(context),
    );
  }

  /// Show audio track selector bottom sheet
  void showAudioTrackSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD000000),
      builder: (_) => _buildTrackSelectorSheet(
        context: context,
        title: 'Audio Track',
        items: availableAudioTracks.value,
        selectedIndex: selectedAudioIndex.value,
        labelBuilder: (item) => (item as AudioTrack).label,
        onSelect: (index) => setAudioTrack(index, context),
      ),
    );
  }

  /// Show subtitle selector bottom sheet
  void showSubtitleSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD000000),
      builder: (_) => _buildSubtitleSelectorSheet(context),
    );
  }

  /// Show settings bottom sheet
  void showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD000000),
      builder: (_) => _buildSettingsSheet(context),
    );
  }

  /// Show playback speed selector
  void showSpeedSelector(BuildContext context) {
    Navigator.of(context).pop(); // Close settings first
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD000000),
      builder: (_) => _buildSpeedSelectorSheet(context),
    );
  }

  /// Show volume slider
  void showVolumeSlider(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xDD000000),
      builder: (_) => _buildVolumeSliderSheet(),
    );
  }

  /// Format duration for display
  String formatDuration(Duration dur) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = dur.inHours;
    final minutes = dur.inMinutes.remainder(60);
    final seconds = dur.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  // Private UI builder methods

  /// Quality selector with Auto option at the top
  Widget _buildQualitySelectorSheet(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: isAutoQuality,
      builder: (context, isAuto, _) {
        return ValueListenableBuilder(
          valueListenable: selectedQualityIndex,
          builder: (context, selectedIndex, _) {
            return ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Video Quality',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Auto option (adaptive bitrate)
                ListTile(
                  leading: Icon(
                    isAuto ? Icons.check_circle : Icons.circle_outlined,
                    color: isAuto ? Colors.red : Colors.white,
                  ),
                  title: Text(
                    'Auto',
                    style: TextStyle(
                      color: isAuto ? Colors.red : Colors.white,
                      fontWeight: isAuto ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: const Text(
                    'Adjusts to network conditions',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () => setAutoQuality(context),
                ),
                const Divider(color: Colors.white24),
                // Individual quality options
                ...List.generate(availableQualities.value.length, (index) {
                  final quality = availableQualities.value[index];
                  final isSelected = !isAuto && index == selectedIndex;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected ? Colors.red : Colors.white,
                    ),
                    title: Text(
                      quality.label,
                      style: TextStyle(
                        color: isSelected ? Colors.red : Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      '${quality.width}x${quality.height}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: () => setQuality(index, context),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTrackSelectorSheet({
    required BuildContext context,
    required String title,
    required List items,
    required int selectedIndex,
    required String Function(dynamic) labelBuilder,
    String Function(dynamic)? subtitleBuilder,
    required Function(int) onSelect,
  }) {
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'No tracks available',
              style: TextStyle(color: Colors.white70),
            ),
          )
        else
          ...List.generate(items.length, (index) {
            final item = items[index];
            final isSelected = index == selectedIndex;
            return ListTile(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Colors.red : Colors.white,
              ),
              title: Text(
                labelBuilder(item),
                style: TextStyle(
                  color: isSelected ? Colors.red : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: subtitleBuilder != null
                  ? Text(
                      subtitleBuilder(item),
                      style: const TextStyle(color: Colors.white70),
                    )
                  : null,
              onTap: () => onSelect(index),
            );
          }),
      ],
    );
  }

  Widget _buildSubtitleSelectorSheet(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: selectedSubtitleIndex,
      builder: (context, selectedIndex, _) {
        return ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Subtitles',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Off option
            ListTile(
              leading: Icon(
                selectedIndex == -1
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: selectedIndex == -1 ? Colors.red : Colors.white,
              ),
              title: Text(
                'Off',
                style: TextStyle(
                  color: selectedIndex == -1 ? Colors.red : Colors.white,
                  fontWeight: selectedIndex == -1
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              onTap: () => setSubtitle(-1, context),
            ),
            ...List.generate(availableSubtitles.value.length, (index) {
              final subtitle = availableSubtitles.value[index];
              final isSelected = index == selectedIndex;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? Colors.red : Colors.white,
                ),
                title: Text(
                  subtitle.label,
                  style: TextStyle(
                    color: isSelected ? Colors.red : Colors.white,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                onTap: () => setSubtitle(index, context),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildSettingsSheet(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.speed, color: Colors.white),
          title: const Text(
            'Playback Speed',
            style: TextStyle(color: Colors.white),
          ),
          onTap: () => showSpeedSelector(context),
        ),
      ],
    );
  }

  Widget _buildSpeedSelectorSheet(BuildContext context) {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    return ListView(
      shrinkWrap: true,
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Playback Speed',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...speeds.map((speed) {
          return ListTile(
            title: Text(
              '${speed}x',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () {
              setSpeed(speed);
              Navigator.of(context).pop();
            },
          );
        }),
      ],
    );
  }

  Widget _buildVolumeSliderSheet() {
    return ValueListenableBuilder(
      valueListenable: volume,
      builder: (context, vol, _) {
        return Container(
          padding: const EdgeInsets.all(24.0),
          height: 250,
          child: Column(
            children: [
              const Text(
                'Volume',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      vol == 0
                          ? Icons.volume_off
                          : vol < 0.5
                          ? Icons.volume_down
                          : Icons.volume_up,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: Colors.red,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: Colors.red,
                          overlayColor: Colors.red.withValues(alpha: 0.2),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: vol,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          label: '${(vol * 100).round()}%',
                          onChanged: setVolume,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${(vol * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
