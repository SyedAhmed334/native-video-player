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

class _VideoFeedPlayerState extends State<VideoFeedPlayer> {
  NativeVideoPlayer? _player;
  int? _textureId;
  bool _isPlaying = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _initializePlayer();
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
    _releasePlayer();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    if (_player != null) return;

    final playerId = 'feed_${widget.index}';
    _player = PlayerManager.instance.acquire(id: playerId);

    _player!.onInitialized = () {
      if (mounted) {
        setState(() {
          _textureId = _player!.textureId;
          _isInitialized = true;
        });
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
        setState(() {
          _isPlaying = playing;
        });
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
        setState(() {
          _textureId = null;
          _isInitialized = false;
          _isPlaying = false;
        });
      }
    }
  }

  void _togglePlayPause() {
    if (_player == null) return;

    if (_isPlaying) {
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
            if (_isInitialized && _textureId != null)
              Texture(textureId: _textureId!)
            else
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),

            // Play/Pause indicator
            if (_isInitialized && !_isPlaying)
              Center(
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
              ),

            // Custom overlay
            if (widget.overlay != null) widget.overlay!,
          ],
        ),
      ),
    );
  }
}
