import 'package:flutter/material.dart';
import '../services/native_video_player.dart';

/// Custom video player widget with Netflix-smooth controls
class CustomVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoPlay;

  const CustomVideoPlayer({super.key, required this.url, this.autoPlay = true});

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  late NativeVideoPlayer _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isLoading = true;
  String _subtitleText = '';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _controller = NativeVideoPlayer();

    // Set up callbacks
    _controller.onInitialized = () {
      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
      if (widget.autoPlay) {
        _controller.play();
      }
    };

    _controller.onPositionUpdate = (position, buffered, duration) {
      setState(() {});
    };

    _controller.onPlaybackStateChanged = (isPlaying) {
      setState(() {});
    };

    _controller.onBufferingStateChanged = (isBuffering) {
      setState(() {
        _isLoading = isBuffering;
      });
    };

    _controller.onSubtitleChanged = (index) {
      if (mounted) setState(() {});
    };

    _controller.onSubtitleText = (text) {
      if (mounted) {
        setState(() {
          _subtitleText = text;
        });
      }
    };

    _controller.onError = (message) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $message')));
    };

    _controller.onQualityChanged = (index) {
      final quality = _controller.availableQualities[index];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quality changed to ${quality.label}'),
          duration: const Duration(seconds: 1),
        ),
      );
    };

    _controller.onAudioChanged = (index) {
      final audio = _controller.availableAudioTracks[index];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Audio changed to ${audio.label}'),
          duration: const Duration(seconds: 1),
        ),
      );
    };

    _controller.onSubtitleChanged = (index) {
      final subtitle = index >= 0
          ? _controller.availableSubtitles[index].label
          : 'Off';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subtitle: $subtitle'),
          duration: const Duration(seconds: 1),
        ),
      );
    };

    // Initialize with URL
    await _controller.initialize(widget.url);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Video texture
            if (_isInitialized && _controller.textureId != null)
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SizedBox.expand(
                    child: Texture(textureId: _controller.textureId!),
                  ),
                ),
              ),

            // Subtitle Overlay
            if (_subtitleText.isNotEmpty)
              Align(
                alignment: const Alignment(0.0, 0.86), // ~87.5% down the screen
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  color: Colors.black54,
                  child: Text(
                    _subtitleText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            // Loading indicator
            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: Colors.red)),

            // Controls overlay
            if (_isInitialized)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showControls = !_showControls;
                  });
                },
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    color: Colors.black54,
                    child: Column(
                      children: [
                        _buildTopBar(),
                        const Spacer(),
                        _buildCenterControls(),
                        const Spacer(),
                        _buildBottomControls(),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          // Quality selector
          IconButton(
            icon: const Icon(Icons.hd, color: Colors.white),
            onPressed: _showQualitySelector,
          ),
          // Audio track selector
          IconButton(
            icon: const Icon(Icons.audiotrack, color: Colors.white),
            onPressed: _showAudioTrackSelector,
          ),
          // Subtitle selector
          IconButton(
            icon: const Icon(Icons.subtitles, color: Colors.white),
            onPressed: _showSubtitleSelector,
          ),
          // Settings
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Rewind 10s
        IconButton(
          icon: const Icon(Icons.replay_10, color: Colors.white, size: 40),
          onPressed: () {
            final newPosition =
                _controller.position - const Duration(seconds: 10);
            _controller.seekTo(
              newPosition.isNegative ? Duration.zero : newPosition,
            );
          },
        ),
        const SizedBox(width: 40),
        // Play/Pause
        IconButton(
          icon: Icon(
            _controller.isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 60,
          ),
          onPressed: () {
            if (_controller.isPlaying) {
              _controller.pause();
            } else {
              _controller.play();
            }
          },
        ),
        const SizedBox(width: 40),
        // Forward 10s
        IconButton(
          icon: const Icon(Icons.forward_10, color: Colors.white, size: 40),
          onPressed: () {
            final newPosition =
                _controller.position + const Duration(seconds: 10);
            _controller.seekTo(
              newPosition > _controller.duration
                  ? _controller.duration
                  : newPosition,
            );
          },
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Column(
      children: [
        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Text(
                _formatDuration(_controller.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: _controller.duration.inMilliseconds > 0
                      ? _controller.position.inMilliseconds /
                            _controller.duration.inMilliseconds
                      : 0.0,
                  onChanged: (value) {
                    final position = Duration(
                      milliseconds:
                          (value * _controller.duration.inMilliseconds).toInt(),
                    );
                    _controller.seekTo(position);
                  },
                  activeColor: Colors.red,
                  inactiveColor: Colors.white30,
                ),
              ),
              Text(
                _formatDuration(_controller.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
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
                onPressed: _showVolumeSlider,
              ),
              const Spacer(),
              // Current quality indicator
              if (_controller.selectedQualityIndex >= 0 &&
                  _controller.selectedQualityIndex <
                      _controller.availableQualities.length)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _controller
                        .availableQualities[_controller.selectedQualityIndex]
                        .label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showQualitySelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
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
            ...List.generate(_controller.availableQualities.length, (index) {
              final quality = _controller.availableQualities[index];
              final isSelected = index == _controller.selectedQualityIndex;
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
                onTap: () {
                  _controller.setQuality(index);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        );
      },
    );
  }

  void _showAudioTrackSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Audio Track',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...List.generate(_controller.availableAudioTracks.length, (index) {
              final audio = _controller.availableAudioTracks[index];
              final isSelected = index == _controller.selectedAudioIndex;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? Colors.red : Colors.white,
                ),
                title: Text(
                  audio.label,
                  style: TextStyle(
                    color: isSelected ? Colors.red : Colors.white,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  _controller.setAudioTrack(index);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        );
      },
    );
  }

  void _showSubtitleSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
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
                _controller.selectedSubtitleIndex == -1
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: _controller.selectedSubtitleIndex == -1
                    ? Colors.red
                    : Colors.white,
              ),
              title: Text(
                'Off',
                style: TextStyle(
                  color: _controller.selectedSubtitleIndex == -1
                      ? Colors.red
                      : Colors.white,
                  fontWeight: _controller.selectedSubtitleIndex == -1
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              onTap: () {
                _controller.setSubtitle(-1);
                Navigator.pop(context);
              },
            ),
            ...List.generate(_controller.availableSubtitles.length, (index) {
              final subtitle = _controller.availableSubtitles[index];
              final isSelected = index == _controller.selectedSubtitleIndex;
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
                onTap: () {
                  _controller.setSubtitle(index);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        );
      },
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
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
            // Playback speed
            ListTile(
              leading: const Icon(Icons.speed, color: Colors.white),
              title: const Text(
                'Playback Speed',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _showSpeedSelector();
              },
            ),
          ],
        );
      },
    );
  }

  void _showSpeedSelector() {
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
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
                  _controller.setSpeed(speed);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ],
        );
      },
    );
  }

  void _showVolumeSlider() {
    double currentVolume = _controller.volume; // Use current volume
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
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
                          currentVolume == 0
                              ? Icons.volume_off
                              : currentVolume < 0.5
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
                              overlayColor: Colors.red.withOpacity(0.2),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: currentVolume,
                              min: 0.0,
                              max: 1.0,
                              divisions: 20,
                              label: '${(currentVolume * 100).round()}%',
                              onChanged: (value) {
                                setState(() {
                                  currentVolume = value;
                                });
                                _controller.setVolume(value);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${(currentVolume * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}
