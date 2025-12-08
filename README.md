# Native Video Player

A premium native video player for Flutter with multi-instance support, HLS/DASH streaming, DRM protection, analytics, and production-ready features.

[![pub package](https://img.shields.io/pub/v/native_video_player.svg)](https://pub.dev/packages/native_video_player)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

### Core
- 🎬 **Native Performance** - ExoPlayer (Android) + AVPlayer (iOS)
- 📱 **Multi-Instance** - Multiple players with LRU eviction
- 🔄 **HLS & DASH** - Adaptive streaming support
- ⚙️ **Quality Switching** - Manual and auto ABR
- 🔊 **Audio Tracks** - Multi-track selection
- 📝 **Subtitles** - Built-in text rendering
- 💾 **Caching** - Segment preloading
- 📺 **Picture-in-Picture** - Native PiP

### Premium (Tier 1)
- 📊 **Analytics Hooks** - Event tracking callbacks
- 🖼️ **Thumbnail Preview** - Seek preview with sprite sheets
- 🔐 **DRM Support** - Widevine (Android) + FairPlay (iOS)
- 📡 **Chromecast/AirPlay** - Full casting support

### Performance (Tier 3)
- 🔄 **Error Recovery** - Auto-retry with categorization
- 📈 **Buffer Health** - Real-time monitoring

---

## Installation

```yaml
dependencies:
  native_video_player: ^1.0.0
```

---

## Quick Start

```dart
import 'package:native_video_player/native_video_player.dart';

CustomVideoPlayer(
  url: 'https://example.com/video.m3u8',
)
```

---

## Complete API

### CustomVideoPlayer Widget

```dart
CustomVideoPlayer(
  url: 'https://example.com/video.m3u8',
  
  // Theming
  theme: VideoPlayerTheme.dark,
  config: VideoPlayerConfig.standard,
  
  // Custom UI
  customControlsBuilder: (context, controller) => MyControls(controller),
  
  // Callbacks
  onReady: () => print('Ready'),
  onComplete: () => print('Finished'),
  onError: (msg) => print('Error: $msg'),
  
  // Analytics
  onAnalyticsEvent: (event) {
    analytics.track(event.type.name, event.toMap());
  },
)
```

### VideoPlayerController

```dart
// Access via customControlsBuilder
controller.play();
controller.pause();
controller.togglePlayPause();
controller.seekTo(Duration(seconds: 30));
controller.rewind(seconds: 10);
controller.forward(seconds: 10);

// State (ValueNotifiers)
controller.isPlaying.value;        // bool
controller.position.value;         // Duration
controller.duration.value;         // Duration
controller.bufferedPosition.value; // Duration
controller.isBuffering.value;      // bool
controller.volume.value;           // double (0.0-1.0)

// Tracks
controller.availableQualities.value;   // List<VideoQuality>
controller.availableAudioTracks.value; // List<AudioTrack>
controller.availableSubtitles.value;   // List<SubtitleTrack>
controller.setQuality(index, context);
controller.setAudioTrack(index, context);
controller.setSubtitle(index, context);

// Error Recovery
controller.hasError.value;     // bool
controller.lastError.value;    // PlaybackError?
controller.clearError();       // Reset and retry

// Buffer Health
controller.bufferHealth.value; // double (0.0-1.0)
controller.isBufferLow.value;  // bool
```

---

## Feed/Stories Mode

### PreloadManager for TikTok/Reels

```dart
class VideoFeed extends StatefulWidget {
  final List<String> urls;
  @override
  State<VideoFeed> createState() => _VideoFeedState();
}

class _VideoFeedState extends State<VideoFeed> {
  late PreloadManager _preloadManager;
  
  @override
  void initState() {
    super.initState();
    _preloadManager = PreloadManager(
      urls: widget.urls,
      config: PreloadConfig.balanced,
    );
  }
  
  @override
  void dispose() {
    _preloadManager.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: widget.urls.length,
      onPageChanged: _preloadManager.onPageChanged,
      itemBuilder: (_, index) => VideoFeedPlayer(
        url: widget.urls[index],
        index: index,
        isActive: true,
        loop: true,
      ),
    );
  }
}
```

---

## DRM Protected Content

### Widevine (Android)

```dart
await player.initialize(
  url,
  drmConfig: DrmConfig.widevine(
    licenseUrl: 'https://license.example.com/widevine',
    headers: {'Authorization': 'Bearer token'},
  ),
);
```

### FairPlay (iOS)

```dart
await player.initialize(
  url,
  drmConfig: DrmConfig.fairPlay(
    licenseUrl: 'https://license.example.com/fairplay',
    certificateUrl: 'https://cert.example.com/fairplay.cer',
    headers: {'Authorization': 'Bearer token'},
  ),
);
```

---

## Chromecast / AirPlay

### CastButton Widget

```dart
// Add to your player controls
CastButton(
  color: Colors.white,
  size: 24,
  onDeviceSelected: (device) {
    print('Connected to ${device.name}');
  },
)
```

### CastService API

```dart
final cast = CastService();

// Initialize
await cast.initialize();

// Get available devices
final devices = await cast.getDevices();

// Connect to device
await cast.castTo(devices.first);

// Load and control media
await cast.loadMedia(
  url: 'https://example.com/video.m3u8',
  title: 'My Video',
  startPosition: Duration(seconds: 30),
);

cast.play();
cast.pause();
cast.seekTo(Duration(minutes: 5));
cast.stop();
cast.disconnect();
```

### Platform Notes

| Platform | Cast Support |
|----------|--------------|
| Android | Full Chromecast SDK |
| iOS | Native AirPlay via Control Center |

---

## Analytics

```dart
CustomVideoPlayer(
  url: url,
  onAnalyticsEvent: (event) {
    // event.type: play, pause, seek, qualityChange, error, etc.
    // event.position: current playback position
    // event.timestamp: when event occurred
    // event.metadata: additional data
    
    myAnalytics.track(event.type.name, event.toMap());
  },
)
```

### Event Types

| Event | Description |
|-------|-------------|
| `play` | Playback started |
| `pause` | Playback paused |
| `seek` | User seeked (includes from/to) |
| `complete` | Video finished |
| `qualityChange` | Quality switched |
| `audioTrackChange` | Audio track changed |
| `subtitleChange` | Subtitle changed |
| `bufferStart` | Buffering started |
| `bufferEnd` | Buffering ended |
| `error` | Playback error |

---

## Thumbnail Preview

```dart
// Configure sprite sheet
final thumbnailConfig = ThumbnailConfig(
  spriteUrl: 'https://example.com/thumbnails.jpg',
  columns: 10,
  rows: 10,
  thumbnailWidth: 160,
  thumbnailHeight: 90,
  interval: Duration(seconds: 5),
);

// Use in seek bar
SeekBarThumbnailPreview(
  config: thumbnailConfig,
  position: seekPosition,
  duration: totalDuration,
  isSeeking: isDragging,
  seekBarWidth: MediaQuery.of(context).size.width,
  seekProgress: progress,
)
```

---

## Error Recovery

```dart
ValueListenableBuilder<PlaybackError?>(
  valueListenable: controller.lastError,
  builder: (context, error, _) {
    if (error == null) return SizedBox.shrink();
    
    return ErrorOverlay(
      error: error,
      onRetry: () {
        controller.clearError();
        controller.nativePlayer.initialize(url);
      },
    );
  },
)
```

### Error Types

| Type | Recoverable | Description |
|------|-------------|-------------|
| `network` | ✅ | Connection lost |
| `server` | ✅ | HTTP error (404, 500) |
| `drm` | ✅ | License error |
| `format` | ❌ | Unsupported codec |
| `source` | ❌ | Invalid URL |
| `decoder` | ❌ | Render error |

---

## Buffer Health

```dart
ValueListenableBuilder<double>(
  valueListenable: controller.bufferHealth,
  builder: (_, health, __) => BufferHealthIndicator(
    health: health,  // 0.0 to 1.0
    isVisible: controller.isPlaying.value,
  ),
)
```

---

## Theming

### Built-in Themes

```dart
VideoPlayerTheme.dark    // Netflix style
VideoPlayerTheme.light   // Light UI
VideoPlayerTheme.minimal // Subtle controls
```

### Custom Theme

```dart
VideoPlayerTheme(
  primaryColor: Colors.purple,
  progressBarColor: Colors.purple,
  controlsBackgroundColor: Colors.black87,
  iconColor: Colors.white,
  iconSize: 28,
  centerIconSize: 64,
)
```

---

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `autoPlay` | bool | true | Auto-start |
| `loop` | bool | false | Loop video |
| `muted` | bool | false | Start muted |
| `volume` | double | 1.0 | Initial volume |
| `seekDuration` | Duration | 10s | Seek amount |
| `controlsAutoHideDuration` | Duration | 3s | Auto-hide delay |
| `showControls` | bool | true | Show controls |
| `enableDoubleTapSeek` | bool | true | Double-tap seek |
| `enableCaching` | bool | false | Segment caching |
| `cacheMaxSizeMB` | int | 100 | Max cache |
| `maxPlayerInstances` | int | 3 | Max players |

### Presets

```dart
VideoPlayerConfig.standard  // Single video
VideoPlayerConfig.feed      // TikTok/Reels optimized
```

---

## Player Manager

```dart
final manager = PlayerManager.instance;

manager.setPoolSize(5);
final player = manager.acquire(id: 'video-1');
await manager.release('video-1');

// Lifecycle
manager.onAppPaused();
manager.onAppResumed();
manager.onMemoryWarning();

// Cache
await manager.clearCache();
final size = await manager.getCacheSize();
```

---

## Platform Setup

### Android

`android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

For PiP:
```xml
<activity
    android:supportsPictureInPicture="true"
    android:configChanges="screenSize|smallestScreenSize|screenLayout|orientation">
```

### iOS

`ios/Runner/Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

For PiP:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

---

## Requirements

- Flutter >= 3.22.0
- Dart >= 3.5.0
- Android minSdk: 21
- iOS: 12.0+

## License

MIT License - see [LICENSE](LICENSE)
