import 'package:flutter/material.dart';
import '../services/native_video_player_service.dart';
import '../player_manager.dart';

/// Lightweight video player widget optimized for feed/story scenarios
/// Features:
/// - Auto-plays when visible
/// - Loops by default
/// - Minimal controls (tap to pause/play)
/// - Uses PlayerManager for pooling
class VideoFeedPlayer extends StatefulWidget {
  /// Video URL to play
  final String url;

  /// Unique index for this video in the feed
  final int index;

  /// Whether this video is currently visible/active
  final bool isActive;

  /// Loop the video
  final bool loop;

  /// Start muted
  final bool muted;

  /// Optional custom overlay
  final Widget? overlay;

  /// Callback when tap to pause/play
  final VoidCallback? onTap;

  const VideoFeedPlayer({
    super.key,
    required this.url,
    required this.index,
    this.isActive = false,
    this.loop = true,
    this.muted = false,
    this.overlay,
    this.onTap,
  });

  @override
  State<VideoFeedPlayer> createState() => _VideoFeedPlayerState();
}

class _VideoFeedPlayerState extends State<VideoFeedPlayer>
    with WidgetsBindingObserver {
  NativeVideoPlayer? _player;
  final ValueNotifier<int?> _textureId = ValueNotifier(null);
  final ValueNotifier<bool> _isPlaying = ValueNotifier(false);
  final ValueNotifier<bool> _isInitialized = ValueNotifier(false);
  bool _wasPlayingBeforeBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      _initializePlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (_player == null) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        if (_isPlaying.value) {
          _wasPlayingBeforeBackground = true;
          _player?.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforeBackground && widget.isActive) {
          _player?.play();
          _wasPlayingBeforeBackground = false;
        }
        break;
      default:
        break;
    }
  }

  @override
  void didUpdateWidget(VideoFeedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle visibility changes
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _initializePlayer();
      } else {
        _releasePlayer();
      }
    }

    // Handle URL changes
    if (widget.url != oldWidget.url && widget.isActive) {
      _releasePlayer();
      _initializePlayer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textureId.dispose();
    _isPlaying.dispose();
    _isInitialized.dispose();
    _releasePlayer();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    if (_player != null) return;

    final playerId = 'feed_${widget.index}';
    _player = PlayerManager.instance.acquire(id: playerId);

    _player!.onInitialized = () {
      if (mounted) {
        _textureId.value = _player!.textureId;
        _isInitialized.value = true;
        if (widget.isActive) {
          _player!.play();
          if (widget.muted) {
            _player!.setVolume(0.0);
          }
        }
      }
    };

    _player!.onPlaybackStateChanged = (playing) {
      if (mounted) {
        _isPlaying.value = playing;
      }
    };

    _player!.onCompleted = () {
      if (widget.loop && mounted) {
        _player!.seekTo(Duration.zero);
        _player!.play();
      }
    };

    await _player!.initialize(widget.url);
  }

  Future<void> _releasePlayer() async {
    if (_player != null) {
      final playerId = _player!.id;
      _player?.pause();
      await PlayerManager.instance.release(playerId);
      _player = null;
      if (mounted) {
        _textureId.value = null;
        _isInitialized.value = false;
        _isPlaying.value = false;
      }
    }
  }

  void _togglePlayPause() {
    if (_player == null) return;

    if (_isPlaying.value) {
      _player!.pause();
    } else {
      _player!.play();
    }

    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video texture
            ValueListenableBuilder<bool>(
              valueListenable: _isInitialized,
              builder: (context, isInitialized, _) {
                if (!isInitialized) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  );
                }
                return ValueListenableBuilder<int?>(
                  valueListenable: _textureId,
                  builder: (context, textureId, _) {
                    if (textureId == null) {
                      return const SizedBox();
                    }
                    return Texture(textureId: textureId);
                  },
                );
              },
            ),

            // Play/Pause indicator
            ValueListenableBuilder<bool>(
              valueListenable: _isInitialized,
              builder: (context, isInitialized, _) {
                if (!isInitialized) return const SizedBox();
                return ValueListenableBuilder<bool>(
                  valueListenable: _isPlaying,
                  builder: (context, isPlaying, _) {
                    if (isPlaying) return const SizedBox();
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            // Custom overlay
            if (widget.overlay != null) widget.overlay!,
          ],
        ),
      ),
    );
  }
}
