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
class FeedDemoScreen extends StatefulWidget {
  const FeedDemoScreen({super.key});

  @override
  State<FeedDemoScreen> createState() => _FeedDemoScreenState();
}

class _FeedDemoScreenState extends State<FeedDemoScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Sample video URLs for feed demo
  static const List<String> _feedVideos = [
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    'https://content.jwplatform.com/manifests/vM7nH0Kl.m3u8',
    'https://playertest.longtailvideo.com/adaptive/elephants_dream_v4/index.m3u8',
    'https://sample.vodobox.net/skate_phantom_flex_4k/skate_phantom_flex_4k.m3u8',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _feedVideos.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              return VideoFeedPlayer(
                url: _feedVideos[index],
                index: index,
                isActive: index == _currentPage,
                loop: true,
                overlay: _buildOverlay(index),
              );
            },
          ),
          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          // Page indicator
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height / 2 - 40,
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
        ],
      ),
    );
  }

  Widget _buildOverlay(int index) {
    return Positioned(
      left: 16,
      right: 80,
      bottom: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Video ${index + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This is a demo of the feed-style video player with preloading support.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
