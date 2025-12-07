import 'dart:developer';

import 'package:get/get.dart';
import '../services/native_video_player.dart';
import '../models/video_track_models.dart';
import 'package:flutter/material.dart';

/// Controller for the Custom Video Player
/// Manages all video player state with reactive observables
class VideoPlayerController extends GetxController {
  final String url;
  final bool autoPlay;

  VideoPlayerController({required this.url, this.autoPlay = true});

  // Native player instance
  late NativeVideoPlayer _nativePlayer;
  NativeVideoPlayer get nativePlayer => _nativePlayer;

  // Reactive state variables
  final isInitialized = false.obs;
  final initialIndexAssigned = false.obs;
  final isLoading = true.obs;
  final isPlaying = false.obs;
  final isBuffering = false.obs;
  final showControls = true.obs;
  final subtitleText = ''.obs;

  // Position and duration
  final position = Duration.zero.obs;
  final bufferedPosition = Duration.zero.obs;
  final duration = Duration.zero.obs;

  // Track lists
  final availableQualities = <VideoQuality>[].obs;
  final availableAudioTracks = <AudioTrack>[].obs;
  final availableSubtitles = <SubtitleTrack>[].obs;

  // Selected track indices
  final selectedQualityIndex = (-1).obs;
  final selectedAudioIndex = (-1).obs;
  final selectedSubtitleIndex = (-1).obs;

  // Volume
  final volume = 1.0.obs;

  // Auto quality mode
  final isAutoQuality = true.obs;

  // Seeking state (prevents position updates during slider drag)
  final isSeeking = false.obs;

  // Retry state
  final isRetrying = false.obs;
  final retryCount = 0.obs;

  // Texture ID
  final textureId = Rxn<int>();

  // Double-tap seek state
  final isDoubleTapSeekingForward = false.obs;
  final isDoubleTapSeekingBackward = false.obs;
  final doubleTapSeekSeconds = 0.obs;
  final doubleTapAnimationKey = 0.obs; // Incremented to trigger new animation

  @override
  void onInit() {
    super.onInit();
    // Defer player initialization to after the navigation animation completes
    // This prevents the screen from stuttering during the transition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePlayer();
    });
  }

  @override
  void onClose() {
    _nativePlayer.dispose();
    super.onClose();
  }

  /// Initialize the native video player
  Future<void> _initializePlayer() async {
    // Ensure loading state is set before starting initialization
    isLoading.value = true;

    _nativePlayer = NativeVideoPlayer();

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

      // Sync track lists
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
    };

    _nativePlayer.onQualityChanged = (index) {
      selectedQualityIndex.value = index;
      _syncTracks();
      if (index >= 0 && index < availableQualities.length) {}
    };

    _nativePlayer.onAudioChanged = (index) {
      selectedAudioIndex.value = index;
      _syncTracks();
      if (index >= 0 && index < availableAudioTracks.length) {}
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

    // Initialize with URL
    await _nativePlayer.initialize(url);
  }

  /// Sync track lists from native player
  void _syncTracks() {
    availableQualities.assignAll(_nativePlayer.availableQualities);
    availableQualities.sort((a, b) {
      // First sort by height
      int heightCompare = b.height.compareTo(a.height);
      if (heightCompare != 0) return heightCompare;

      // If equal, sort by width
      int widthCompare = b.width.compareTo(a.width);
      if (widthCompare != 0) return widthCompare;

      // If still equal, sort by bitrate
      return b.bitrate.compareTo(a.bitrate);
    });
    availableAudioTracks.assignAll(
      _nativePlayer.availableAudioTracks
          .where(
            (track) => track.language != 'Unknown' && track.label != 'Unknown',
          )
          .toList(),
    );
    availableSubtitles.assignAll(
      _nativePlayer.availableSubtitles
          .where(
            (track) => track.language != 'Unknown' && track.label != 'Unknown',
          )
          .toList(),
    );
    selectedQualityIndex.value = _nativePlayer.selectedQualityIndex;
    selectedAudioIndex.value = _nativePlayer.selectedAudioIndex;
    selectedSubtitleIndex.value = _nativePlayer.selectedSubtitleIndex;
    volume.value = _nativePlayer.volume;
    isAutoQuality.value = _nativePlayer.isAutoQuality;
    if (availableAudioTracks.isNotEmpty && !initialIndexAssigned.value) {
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
  }

  /// Pause video
  void pause() {
    _nativePlayer.pause();
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
    _nativePlayer.seekTo(pos);
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
  void setQuality(int index) {
    _nativePlayer.setQuality(index);
    isAutoQuality.value = false;
    Get.back();
  }

  /// Set auto quality (adaptive bitrate)
  void setAutoQuality() {
    _nativePlayer.setAutoQuality();
    isAutoQuality.value = true;
    Get.back();
  }

  /// Set audio track
  void setAudioTrack(int index) {
    _nativePlayer.setAudioTrack(index);
    Get.back();
  }

  /// Set subtitle track (-1 to disable)
  void setSubtitle(int index) {
    _nativePlayer.setSubtitle(index);
    Get.back();
  }

  /// Retry connection after failure
  void retryConnection() {
    _nativePlayer.retryConnection();
  }

  /// Show quality selector bottom sheet
  void showQualitySelector() {
    Get.bottomSheet(
      _buildQualitySelectorSheet(),
      backgroundColor: const Color(0xDD000000),
    );
  }

  /// Show audio track selector bottom sheet
  void showAudioTrackSelector() {
    Get.bottomSheet(
      _buildTrackSelectorSheet(
        title: 'Audio Track',
        items: availableAudioTracks,
        selectedIndex: selectedAudioIndex.value,
        labelBuilder: (item) => (item as AudioTrack).label,
        onSelect: (index) => setAudioTrack(index),
      ),
      backgroundColor: const Color(0xDD000000),
    );
  }

  /// Show subtitle selector bottom sheet
  void showSubtitleSelector() {
    Get.bottomSheet(
      _buildSubtitleSelectorSheet(),
      backgroundColor: const Color(0xDD000000),
    );
  }

  /// Show settings bottom sheet
  void showSettings() {
    Get.bottomSheet(
      _buildSettingsSheet(),
      backgroundColor: const Color(0xDD000000),
    );
  }

  /// Show playback speed selector
  void showSpeedSelector() {
    Get.back();
    Get.bottomSheet(
      _buildSpeedSelectorSheet(),
      backgroundColor: const Color(0xDD000000),
    );
  }

  /// Show volume slider
  void showVolumeSlider() {
    Get.bottomSheet(
      _buildVolumeSliderSheet(),
      backgroundColor: const Color(0xDD000000),
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
  Widget _buildQualitySelectorSheet() {
    return Obx(
      () => ListView(
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
              isAutoQuality.value ? Icons.check_circle : Icons.circle_outlined,
              color: isAutoQuality.value ? Colors.red : Colors.white,
            ),
            title: Text(
              'Auto',
              style: TextStyle(
                color: isAutoQuality.value ? Colors.red : Colors.white,
                fontWeight: isAutoQuality.value
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            subtitle: const Text(
              'Adjusts to network conditions',
              style: TextStyle(color: Colors.white70),
            ),
            onTap: setAutoQuality,
          ),
          const Divider(color: Colors.white24),
          // Individual quality options
          ...List.generate(availableQualities.length, (index) {
            final quality = availableQualities[index];
            final isSelected =
                !isAutoQuality.value && index == selectedQualityIndex.value;
            return ListTile(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Colors.red : Colors.white,
              ),
              title: Text(
                quality.label,
                style: TextStyle(
                  color: isSelected ? Colors.red : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                '${quality.width}x${quality.height}',
                style: const TextStyle(color: Colors.white70),
              ),
              onTap: () => setQuality(index),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTrackSelectorSheet({
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

  Widget _buildSubtitleSelectorSheet() {
    return Obx(
      () => ListView(
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
              selectedSubtitleIndex.value == -1
                  ? Icons.check_circle
                  : Icons.circle_outlined,
              color: selectedSubtitleIndex.value == -1
                  ? Colors.red
                  : Colors.white,
            ),
            title: Text(
              'Off',
              style: TextStyle(
                color: selectedSubtitleIndex.value == -1
                    ? Colors.red
                    : Colors.white,
                fontWeight: selectedSubtitleIndex.value == -1
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            onTap: () => setSubtitle(-1),
          ),
          ...List.generate(availableSubtitles.length, (index) {
            final subtitle = availableSubtitles[index];
            final isSelected = index == selectedSubtitleIndex.value;
            return ListTile(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Colors.red : Colors.white,
              ),
              title: Text(
                subtitle.label,
                style: TextStyle(
                  color: isSelected ? Colors.red : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              onTap: () => setSubtitle(index),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSettingsSheet() {
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
          onTap: showSpeedSelector,
        ),
      ],
    );
  }

  Widget _buildSpeedSelectorSheet() {
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
              Get.back();
            },
          );
        }),
      ],
    );
  }

  Widget _buildVolumeSliderSheet() {
    return Obx(
      () => Container(
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
                    volume.value == 0
                        ? Icons.volume_off
                        : volume.value < 0.5
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
                        value: volume.value,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        label: '${(volume.value * 100).round()}%',
                        onChanged: setVolume,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(volume.value * 100).round()}%',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
