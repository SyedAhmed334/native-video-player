# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-12-08

### Added
- Initial release
- Multi-instance video player support
- ExoPlayer (Android) and AVPlayer (iOS) backends
- HLS and DASH streaming support
- Quality switching (manual and auto)
- Audio track selection
- Subtitle rendering
- Segment caching for smoother playback
- PreloadManager for feed-style UIs
- VideoPlayerTheme with dark, light, and minimal presets
- VideoPlayerConfig with standard and feed presets
- CustomVideoPlayer with customControlsBuilder support
- VideoFeedPlayer for lightweight feed scenarios
- PlayerManager for instance pooling
- App lifecycle management (pause on background)
- Memory warning handling
- Picture-in-Picture support

### Platforms
- Android minSdk: 21
- iOS: 12.0+
