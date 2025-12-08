import 'package:flutter/material.dart';
import '../video_player_controller.dart';
import '../models/video_player_theme.dart';
import '../models/video_player_config.dart';

/// Signature for building custom controls overlay
typedef CustomControlsBuilder =
    Widget Function(BuildContext context, VideoPlayerController controller);

/// Custom video player widget with Netflix-smooth controls
/// Handles app lifecycle (pause on background) and graceful disposal
class CustomVideoPlayer extends StatefulWidget {
  /// Video URL to play
  final String url;

  /// Auto-start playback when initialized (deprecated, use config.autoPlay)
  final bool autoPlay;

  /// Theme configuration for the player UI
  final VideoPlayerTheme theme;

  /// Player behavior configuration
  final VideoPlayerConfig config;

  /// Optional custom controls overlay builder
  /// When provided, replaces the default controls with your custom implementation
  final CustomControlsBuilder? customControlsBuilder;

  /// Callback when player is ready
  final VoidCallback? onReady;

  /// Callback when playback completes
  final VoidCallback? onComplete;

  /// Callback when an error occurs
  final void Function(String message)? onError;

  const CustomVideoPlayer({
    super.key,
    required this.url,
    this.autoPlay = true,
    this.theme = VideoPlayerTheme.dark,
    this.config = VideoPlayerConfig.standard,
    this.customControlsBuilder,
    this.onReady,
    this.onComplete,
    this.onError,
  });

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer>
    with WidgetsBindingObserver {
  late VideoPlayerController controller;
  bool _wasPlayingBeforeBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize the controller using config
    controller = VideoPlayerController(
      url: widget.url,
      autoPlay: widget.config.autoPlay,
    );
    controller.initialize();

    // Listen for initialization
    controller.isInitialized.addListener(_onInitialized);

    // Listen for completion (position reaches duration)
    controller.position.addListener(_checkCompletion);

    // Set up UI callbacks
    controller.onError = (message) {
      widget.onError?.call(message);
      if (mounted) {
        debugPrint('[CustomVideoPlayer] Error: $message');
      }
    };

    controller.onNetworkChanged = (isConnected, type) {
      debugPrint('[CustomVideoPlayer] Network: $isConnected, $type');
    };

    // Apply initial volume from config
    if (widget.config.muted) {
      controller.setVolume(0.0);
    } else {
      controller.setVolume(widget.config.volume);
    }
  }

  void _onInitialized() {
    if (controller.isInitialized.value) {
      widget.onReady?.call();
    }
  }

  void _checkCompletion() {
    final pos = controller.position.value;
    final dur = controller.duration.value;
    // Check if playback completed (reached end)
    if (dur.inSeconds > 0 &&
        pos.inSeconds >= dur.inSeconds &&
        !controller.isPlaying.value) {
      widget.onComplete?.call();
      // Handle loop from config
      if (widget.config.loop) {
        controller.seekTo(Duration.zero);
        controller.play();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.isInitialized.removeListener(_onInitialized);
    controller.position.removeListener(_checkCompletion);
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Don't pause if we're in Picture-in-Picture mode
        if (controller.isPiPActive.value) {
          return;
        }
        // App going to background - pause video
        _wasPlayingBeforeBackground = controller.isPlaying.value;
        if (_wasPlayingBeforeBackground) {
          controller.pause();
        }
        break;
      case AppLifecycleState.resumed:
        // App coming back to foreground - resume if was playing
        if (_wasPlayingBeforeBackground) {
          controller.play();
          _wasPlayingBeforeBackground = false;
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App being destroyed - handled by dispose
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          controller.pause();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // Video texture
              ValueListenableBuilder<bool>(
                valueListenable: controller.isInitialized,
                builder: (context, isInitialized, _) {
                  return ValueListenableBuilder<int?>(
                    valueListenable: controller.textureId,
                    builder: (context, textureId, _) {
                      if (isInitialized && textureId != null) {
                        return Center(
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: SizedBox.expand(
                              child: Texture(textureId: textureId),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),

              // Subtitle Overlay
              ValueListenableBuilder<String>(
                valueListenable: controller.subtitleText,
                builder: (context, text, _) {
                  if (text.isNotEmpty) {
                    return Align(
                      alignment: const Alignment(0.0, 0.86),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        color: Colors.black54,
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Loading indicator
              AnimatedBuilder(
                animation: Listenable.merge([
                  controller.isLoading,
                  controller.isBuffering,
                  controller.isInitialized,
                ]),
                builder: (context, _) {
                  if (controller.isLoading.value ||
                      controller.isBuffering.value ||
                      !controller.isInitialized.value) {
                    return Container(
                      color: Colors.black87,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.red),
                            SizedBox(height: 16),
                            Text(
                              'Loading...',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Controls overlay (BELOW double-tap zones so it doesn't block gestures)
              // Use customControlsBuilder if provided, otherwise use default controls
              if (widget.customControlsBuilder != null)
                widget.customControlsBuilder!(context, controller)
              else
                ValueListenableBuilder<bool>(
                  valueListenable: controller.isInitialized,
                  builder: (context, isInitialized, _) {
                    if (isInitialized) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: controller.showControls,
                        builder: (context, showControls, _) {
                          return IgnorePointer(
                            ignoring:
                                true, // Always ignore pointer - gestures handled by double-tap zones
                            child: AnimatedOpacity(
                              opacity: showControls ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                color: widget.theme.controlsBackgroundColor,
                                child: Column(
                                  children: [
                                    _buildTopBar(context, controller),
                                    const Spacer(),
                                    _buildBottomControls(context, controller),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

              // Double-tap seek zones (on top for gesture detection)
              ValueListenableBuilder<bool>(
                valueListenable: controller.isInitialized,
                builder: (context, isInitialized, _) {
                  if (isInitialized) {
                    return Stack(
                      children: [
                        Row(
                          children: [
                            // Left zone - backward seek
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onDoubleTap: () => controller
                                    .doubleTapSeekBackward(seconds: 10),
                                onTap: controller.toggleControls,
                                child: const SizedBox.expand(),
                              ),
                            ),
                            // Right zone - forward seek
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onDoubleTap: () => controller
                                    .doubleTapSeekForward(seconds: 10),
                                onTap: controller.toggleControls,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ],
                        ),
                        // Control buttons that need to be tappable
                        ValueListenableBuilder<bool>(
                          valueListenable: controller.showControls,
                          builder: (context, showControls, _) {
                            if (showControls) {
                              return Stack(
                                children: [
                                  // Top bar buttons
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: _buildTopBar(context, controller),
                                  ),
                                  // Center controls
                                  Positioned.fill(
                                    child: Center(
                                      child: _buildCenterControls(controller),
                                    ),
                                  ),
                                  // Bottom controls
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: _buildBottomControls(
                                      context,
                                      controller,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Backward seek animation overlay (left side)
              ValueListenableBuilder<bool>(
                valueListenable: controller.isDoubleTapSeekingBackward,
                builder: (context, isSeekingBackward, _) {
                  if (isSeekingBackward) {
                    return Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: MediaQuery.of(context).size.width * 0.4,
                      child: IgnorePointer(
                        child: ValueListenableBuilder<int>(
                          valueListenable: controller.doubleTapAnimationKey,
                          builder: (context, key, _) {
                            return _DoubleTapSeekAnimation(
                              key: ValueKey('backward_$key'),
                              isForward: false,
                              seconds: controller.doubleTapSeekSeconds.value,
                            );
                          },
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Forward seek animation overlay (right side)
              ValueListenableBuilder<bool>(
                valueListenable: controller.isDoubleTapSeekingForward,
                builder: (context, isSeekingForward, _) {
                  if (isSeekingForward) {
                    return Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: MediaQuery.of(context).size.width * 0.4,
                      child: IgnorePointer(
                        child: ValueListenableBuilder<int>(
                          valueListenable: controller.doubleTapAnimationKey,
                          builder: (context, key, _) {
                            return _DoubleTapSeekAnimation(
                              key: ValueKey('forward_$key'),
                              isForward: true,
                              seconds: controller.doubleTapSeekSeconds.value,
                            );
                          },
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, VideoPlayerController controller) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          // Quality selector
          IconButton(
            icon: const Icon(Icons.hd, color: Colors.white),
            onPressed: () => controller.showQualitySelector(context),
          ),
          // Audio track selector
          IconButton(
            icon: const Icon(Icons.audiotrack, color: Colors.white),
            onPressed: () => controller.showAudioTrackSelector(context),
          ),
          // Subtitle selector
          IconButton(
            icon: const Icon(Icons.subtitles, color: Colors.white),
            onPressed: () => controller.showSubtitleSelector(context),
          ),
          // Picture-in-Picture
          IconButton(
            icon: const Icon(Icons.picture_in_picture, color: Colors.white),
            onPressed: () => controller.enterPiP(context),
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => controller.showSettings(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControls(VideoPlayerController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Rewind 10s
        IconButton(
          icon: const Icon(Icons.replay_10, color: Colors.white, size: 40),
          onPressed: controller.rewind,
        ),
        const SizedBox(width: 40),
        // Play/Pause
        ValueListenableBuilder<bool>(
          valueListenable: controller.isPlaying,
          builder: (context, isPlaying, _) {
            return IconButton(
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 60,
              ),
              onPressed: controller.togglePlayPause,
            );
          },
        ),
        const SizedBox(width: 40),
        // Forward 10s
        IconButton(
          icon: const Icon(Icons.forward_10, color: Colors.white, size: 40),
          onPressed: controller.forward,
        ),
      ],
    );
  }

  Widget _buildBottomControls(
    BuildContext context,
    VideoPlayerController controller,
  ) {
    return Column(
      children: [
        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              ValueListenableBuilder<Duration>(
                valueListenable: controller.position,
                builder: (context, position, _) {
                  return Text(
                    controller.formatDuration(position),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  );
                },
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    controller.position,
                    controller.duration,
                  ]),
                  builder: (context, _) {
                    return Slider(
                      value: controller.duration.value.inMilliseconds > 0
                          ? (controller.position.value.inMilliseconds /
                                    controller.duration.value.inMilliseconds)
                                .clamp(0.0, 1.0)
                          : 0.0,

                      /// When user starts dragging
                      onChangeStart: (value) {
                        controller.isSeeking.value = true;
                      },

                      /// When slider value is changing - update UI only, no native seek
                      onChanged: (value) {
                        // Update position locally for immediate UI feedback
                        controller.position.value = Duration(
                          milliseconds:
                              (value * controller.duration.value.inMilliseconds)
                                  .toInt(),
                        );
                      },

                      /// When user stops dragging - perform actual seek
                      onChangeEnd: (value) {
                        final position = Duration(
                          milliseconds:
                              (value * controller.duration.value.inMilliseconds)
                                  .toInt(),
                        );
                        controller.seekTo(position);
                        controller.isSeeking.value = false;
                      },

                      activeColor: Colors.red,
                      inactiveColor: Colors.white30,
                    );
                  },
                ),
              ),

              ValueListenableBuilder<Duration>(
                valueListenable: controller.duration,
                builder: (context, duration, _) {
                  return Text(
                    controller.formatDuration(duration),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  );
                },
              ),
            ],
          ),
        ),
        // Additional controls
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0, left: 16.0, right: 16.0),
          child: Row(
            children: [
              // Volume
              IconButton(
                icon: const Icon(Icons.volume_up, color: Colors.white),
                onPressed: () => controller.showVolumeSlider(context),
              ),
              const Spacer(),
              // Current quality indicator
              AnimatedBuilder(
                animation: Listenable.merge([
                  controller.isAutoQuality,
                  controller.selectedQualityIndex,
                  controller.availableQualities,
                ]),
                builder: (context, _) {
                  // Show "Auto" when auto quality is enabled
                  if (controller.isAutoQuality.value) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Auto',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }
                  // Show selected quality label
                  if (controller.selectedQualityIndex.value >= 0 &&
                      controller.selectedQualityIndex.value <
                          controller.availableQualities.value.length) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        controller
                            .availableQualities
                            .value[controller.selectedQualityIndex.value]
                            .label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Animated widget for double-tap seek feedback (YouTube-style)
class _DoubleTapSeekAnimation extends StatefulWidget {
  final bool isForward;
  final int seconds;

  const _DoubleTapSeekAnimation({
    super.key,
    required this.isForward,
    required this.seconds,
  });

  @override
  State<_DoubleTapSeekAnimation> createState() =>
      _DoubleTapSeekAnimationState();
}

class _DoubleTapSeekAnimationState extends State<_DoubleTapSeekAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rippleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _iconAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _rippleAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );

    _iconAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: widget.isForward
              ? Alignment.centerLeft
              : Alignment.centerRight,
          children: [
            // Ripple effect background
            Positioned.fill(
              child: ClipPath(
                clipper: _SemiCircleClipper(isForward: widget.isForward),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: widget.isForward
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      radius: _rippleAnimation.value,
                      colors: [
                        Colors.white.withValues(
                          alpha: 0.3 * _fadeAnimation.value,
                        ),
                        Colors.white.withValues(
                          alpha: 0.1 * _fadeAnimation.value,
                        ),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Icon and text
            Positioned(
              left: widget.isForward ? 100 : null,
              right: widget.isForward ? null : 100,
              child: Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: 0.8 + (0.2 * _iconAnimation.value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animated arrows
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.isForward
                            ? [_buildArrow(0.0)]
                            : [_buildArrow(0.0, reverse: true)],
                      ),
                      const SizedBox(height: 8),
                      // Seconds text
                      Text(
                        '${widget.seconds} seconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(blurRadius: 4, color: Colors.black54),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArrow(double delay, {bool reverse = false}) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(reverse ? (1 - value) * -10 : (1 - value) * 10, 0),
            child: Icon(
              reverse ? Icons.fast_rewind : Icons.fast_forward,
              color: Colors.white,
              size: 32,
            ),
          ),
        );
      },
    );
  }
}

/// Clips the widget to create a semi-circle shape for the ripple effect
class _SemiCircleClipper extends CustomClipper<Path> {
  final bool isForward;

  _SemiCircleClipper({required this.isForward});

  @override
  Path getClip(Size size) {
    final path = Path();
    if (isForward) {
      // Left side semi-circle (curves to the right)
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.quadraticBezierTo(size.width * 1.2, size.height / 2, 0, 0);
    } else {
      // Right side semi-circle (curves to the left)
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.quadraticBezierTo(-size.width * 0.2, size.height / 2, size.width, 0);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
