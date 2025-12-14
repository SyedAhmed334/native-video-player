import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Custom Video Player Demo',
      theme: ThemeData(primarySwatch: Colors.red, brightness: Brightness.dark),
      home: const VideoListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VideoListScreen extends StatelessWidget {
  const VideoListScreen({super.key});

  // Example video URLs for testing
  static const List<VideoItem> videos = [
    VideoItem(
      title: 'Big Buck Bunny (MP4)',
      url:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      description: 'Standard MP4 format',
    ),
    VideoItem(
      title: 'Sintel (HLS)',
      url: 'https://content.jwplatform.com/manifests/vM7nH0Kl.m3u8',
      description: 'HLS adaptive streaming with multiple qualities',
    ),
    VideoItem(
      title: 'Tears of Steel (DASH)',
      url:
          'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.mp4/.m3u8',
      description: 'DASH adaptive streaming',
    ),
    VideoItem(
      title: 'Elephant Dream v4 (HLS)',
      url:
          'https://playertest.longtailvideo.com/adaptive/elephants_dream_v4/index.m3u8',
      description: 'HLS adaptive with multiple qualities - JW Player test',
    ),
    VideoItem(
      title: 'Big Buck(HLS)',
      url:
          'https://sample.vodobox.net/skate_phantom_flex_4k/skate_phantom_flex_4k.m3u8',
      description: 'Big Buck Bunny HLS',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Video Player'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.grey[900]!, Colors.black],
          ),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: videos.length,
          itemBuilder: (context, index) {
            final video = videos[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              color: Colors.grey[850],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CustomVideoPlayer(url: video.url, autoPlay: true),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              video.description,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white54),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'feed',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FeedDemoScreen()),
              );
            },
            backgroundColor: Colors.purple,
            child: const Icon(Icons.view_carousel),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'custom',
            onPressed: () {
              _showCustomUrlDialog(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('Custom URL'),
            backgroundColor: Colors.red,
          ),
        ],
      ),
    );
  }

  void _showCustomUrlDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Text(
            'Enter Video URL',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'https://example.com/video.m3u8',
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white54),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.red),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CustomVideoPlayer(
                        url: controller.text,
                        autoPlay: true,
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Play'),
            ),
          ],
        );
      },
    );
  }
}

class VideoItem {
  final String title;
  final String url;
  final String description;

  const VideoItem({
    required this.title,
    required this.url,
    required this.description,
  });
}

/// Demo screen showing TikTok/Reels-style vertical video feed
/// Tests caching, preloading, and network resilience
class FeedDemoScreen extends StatefulWidget {
  const FeedDemoScreen({super.key});

  @override
  State<FeedDemoScreen> createState() => _FeedDemoScreenState();
}

class _FeedDemoScreenState extends State<FeedDemoScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  int _cacheSize = 0;
  bool _isNetworkConnected = true;
  String _networkType = 'unknown';

  // TikTok-style video feed URLs
  static const List<String> _feedVideos = [
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
    "https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4",
  ];

  static const List<String> _videoTitles = [
    "Big Buck Bunny",
    "Elephant's Dream",
    "Sintel",
    "Tears of Steel",
    "For Bigger Blazes",
    "For Bigger Escapes",
    "For Bigger Fun",
    "For Bigger Joyrides",
    "For Bigger Meltdowns",
    "Big Buck Bunny (1MB)",
  ];

  // Preloading controllers - No longer needed!
  // Headless prefetching is stateless on Dart side

  @override
  void initState() {
    super.initState();
    _updateCacheSize();
    // Use addPostFrameCallback to start preloading after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadNextVideos(0);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _preloadNextVideos(int currentIndex) async {
    // Determine which indices to preload (next 4 videos)
    // TikTok-style: Just tell native to download the bytes.
    // We don't need to keep any controllers alive!
    for (int i = 1; i <= 4; i++) {
      if (currentIndex + i < _feedVideos.length) {
        final url = _feedVideos[currentIndex + i];
        print("Prefetching (Headless) video ${currentIndex + i}: $url");
        NativeVideoPlayer.prefetchHeadless(url);
      }
    }

    // We update cache size occasionally to show progress
    Future.delayed(const Duration(seconds: 2), _updateCacheSize);
  }

  Future<void> _updateCacheSize() async {
    final size = await NativeVideoPlayer.getCacheSize();
    if (mounted) {
      setState(() => _cacheSize = size);
    }
  }

  void _onNetworkChanged(bool isConnected, String type) {
    if (mounted) {
      setState(() {
        _isNetworkConnected = isConnected;
        _networkType = type;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video feed
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _feedVideos.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              _updateCacheSize();
              _preloadNextVideos(index);
            },
            itemBuilder: (context, index) {
              return VideoFeedPlayer(
                url: _feedVideos[index],
                index: index,
                isActive: index == _currentPage,
                loop: true,
                onNetworkChanged: _onNetworkChanged,
                overlay: _buildOverlay(index),
              );
            },
          ),

          // Top bar with back button and status
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  // Status indicators
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Network status
                        Icon(
                          _isNetworkConnected
                              ? (_networkType == 'wifi'
                                    ? Icons.wifi
                                    : Icons.signal_cellular_4_bar)
                              : Icons.wifi_off,
                          color: _isNetworkConnected
                              ? Colors.green
                              : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        // Cache size
                        Icon(
                          Icons.storage,
                          color: _cacheSize > 0 ? Colors.blue : Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatBytes(_cacheSize),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Page indicator (right side)
          Positioned(
            right: 12,
            top:
                MediaQuery.of(context).size.height / 2 -
                (_feedVideos.length * 6),
            child: Column(
              children: List.generate(
                _feedVideos.length,
                (i) => Container(
                  width: 4,
                  height: i == _currentPage ? 16 : 8,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: i == _currentPage ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),

          // Actions (right side, like TikTok)
          Positioned(
            right: 12,
            bottom: 120,
            child: Column(
              children: [
                _buildActionButton(
                  icon: Icons.favorite,
                  label: '${(_currentPage + 1) * 1234}',
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                _buildActionButton(
                  icon: Icons.comment,
                  label: '${(_currentPage + 1) * 89}',
                ),
                const SizedBox(height: 24),
                _buildActionButton(icon: Icons.share, label: 'Share'),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () async {
                    await NativeVideoPlayer.clearCache();
                    _updateCacheSize();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cache cleared'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Clear\nCache',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color ?? Colors.white, size: 28),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildOverlay(int index) {
    return Positioned(
      left: 16,
      right: 80,
      bottom: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Creator info
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    _videoTitles[index][0],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '@demo_creator',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Follow',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Title
          Text(
            _videoTitles[index],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          // Description
          Text(
            'Video ${index + 1} of ${_feedVideos.length} • Testing caching & preloading',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          // Music/Sound row (like TikTok)
          Row(
            children: [
              const Icon(Icons.music_note, color: Colors.white70, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Original Sound - Demo Creator',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class VideoFeedPlayer extends StatefulWidget {
  final String url;
  final int index;
  final bool isActive;
  final bool loop;
  final Function(bool, String)? onNetworkChanged;
  final Widget? overlay;

  const VideoFeedPlayer({
    super.key,
    required this.url,
    required this.index,
    required this.isActive,
    this.loop = false,
    this.onNetworkChanged,
    this.overlay,
  });

  @override
  State<VideoFeedPlayer> createState() => _VideoFeedPlayerState();
}

class _VideoFeedPlayerState extends State<VideoFeedPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController(
      url: widget.url,
      autoPlay: widget.isActive,
    );

    _initializePlayer();
  }

  void _initializePlayer() {
    // Set network callback
    if (widget.onNetworkChanged != null) {
      _controller.onNetworkChanged = (connected, type) {
        widget.onNetworkChanged!(connected, type);
      };
    }

    _controller.initialize();
    _controller.isInitialized.addListener(() {
      if (mounted) {
        setState(() => _isInitialized = _controller.isInitialized.value);
        if (_isInitialized && widget.isActive) {
          _controller.play();
        }
      }
    });

    _controller.onError = (message) {
      print("[VideoFeedPlayer] Error: $message");
    };
  }

  @override
  void didUpdateWidget(VideoFeedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.play();
      } else {
        _controller.pause();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video
        if (_isInitialized)
          ValueListenableBuilder<int?>(
            valueListenable: _controller.textureId,
            builder: (context, textureId, _) {
              if (textureId != null) {
                return SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller.availableQualities.value.isNotEmpty
                          ? _controller.availableQualities.value.first.width
                                .toDouble()
                          : 1080,
                      height: _controller.availableQualities.value.isNotEmpty
                          ? _controller.availableQualities.value.first.height
                                .toDouble()
                          : 1920,
                      child: Texture(textureId: textureId),
                    ),
                  ),
                );
              }
              return Container(color: Colors.black);
            },
          )
        else
          Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),

        // Overlay
        if (widget.overlay != null) widget.overlay!,

        // Play/Pause indicator (simple tap)
        GestureDetector(
          onTap: () {
            if (_controller.isPlaying.value) {
              _controller.pause();
            } else {
              _controller.play();
            }
          },
          behavior: HitTestBehavior.translucent,
        ),
      ],
    );
  }
}
