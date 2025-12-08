import 'dart:async';
import 'dart:developer';
import 'services/native_video_player_service.dart';
import 'player_manager.dart';

/// Configuration for preload behavior
class PreloadConfig {
  /// Number of videos to preload ahead of current position
  final int preloadAhead;

  /// Number of videos to preload behind current position
  final int preloadBehind;

  /// Whether to start playback after preload (muted)
  final bool warmupPlayback;

  const PreloadConfig({
    this.preloadAhead = 1,
    this.preloadBehind = 1,
    this.warmupPlayback = false,
  });

  /// Minimal preloading - just next video
  static const minimal = PreloadConfig(preloadAhead: 1, preloadBehind: 0);

  /// Balanced preloading - 1 ahead, 1 behind
  static const balanced = PreloadConfig(preloadAhead: 1, preloadBehind: 1);

  /// Aggressive preloading - 2 ahead, 1 behind
  static const aggressive = PreloadConfig(preloadAhead: 2, preloadBehind: 1);
}

/// Manages intelligent preloading of videos in feed-style UIs
///
/// Usage:
/// ```dart
/// final preloadManager = PreloadManager(
///   urls: ['url1', 'url2', 'url3'],
///   config: PreloadConfig.balanced,
/// );
///
/// // When user swipes to index 1
/// preloadManager.onPageChanged(1);
///
/// // Get player for current page
/// final player = preloadManager.getPlayer(1);
/// ```
class PreloadManager {
  /// List of video URLs to manage
  final List<String> _urls;

  /// Preload configuration
  final PreloadConfig config;

  /// Map of index -> player ID for tracking
  final Map<int, String> _indexToPlayerId = {};

  /// Map of player ID -> index for reverse lookup
  final Map<String, int> _playerIdToIndex = {};

  /// Current page index
  int _currentIndex = 0;

  /// Whether the manager is disposed
  bool _isDisposed = false;

  /// Debounce timer for rapid page changes
  Timer? _debounceTimer;

  /// Creates a PreloadManager with the given URLs
  PreloadManager({
    required List<String> urls,
    this.config = const PreloadConfig(),
  }) : _urls = List.from(urls) {
    log(
      '[PreloadManager] Created with ${urls.length} URLs, config: ahead=${config.preloadAhead}, behind=${config.preloadBehind}',
    );
  }

  /// Get number of managed URLs
  int get length => _urls.length;

  /// Get current index
  int get currentIndex => _currentIndex;

  /// Get list of currently preloaded indices
  List<int> get preloadedIndices => _indexToPlayerId.keys.toList()..sort();

  /// Called when the visible page changes (e.g., from PageView.onPageChanged)
  /// This triggers preloading of adjacent videos
  void onPageChanged(int index) {
    if (_isDisposed) return;
    if (index < 0 || index >= _urls.length) return;

    _currentIndex = index;

    // Debounce rapid page changes
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      _updatePreloadedPlayers();
    });
  }

  /// Get the player for a specific index
  /// Returns null if index is out of range or player not yet created
  NativeVideoPlayer? getPlayer(int index) {
    if (index < 0 || index >= _urls.length) return null;

    final playerId = _indexToPlayerId[index];
    if (playerId == null) {
      // Player not preloaded, create it now
      return _createPlayer(index);
    }

    return PlayerManager.instance.get(playerId);
  }

  /// Get or create player for an index - ensures player exists
  Future<NativeVideoPlayer> getOrCreatePlayer(int index) async {
    if (index < 0 || index >= _urls.length) {
      throw RangeError('Index $index out of range [0, ${_urls.length})');
    }

    var player = getPlayer(index);
    if (player != null) return player;

    // Create and initialize
    player = _createPlayer(index)!;
    await player.initialize(_urls[index]);
    return player;
  }

  /// Update preloaded players based on current index
  void _updatePreloadedPlayers() {
    if (_isDisposed) return;

    // Calculate desired preload range
    final startIndex = (_currentIndex - config.preloadBehind).clamp(
      0,
      _urls.length - 1,
    );
    final endIndex = (_currentIndex + config.preloadAhead).clamp(
      0,
      _urls.length - 1,
    );

    final desiredIndices = Set<int>.from(
      List.generate(endIndex - startIndex + 1, (i) => startIndex + i),
    );

    // Release players outside the preload window
    final indicesToRelease = _indexToPlayerId.keys
        .where((i) => !desiredIndices.contains(i))
        .toList();

    for (final index in indicesToRelease) {
      _releasePlayer(index);
    }

    // Preload players in the desired range
    for (final index in desiredIndices) {
      if (!_indexToPlayerId.containsKey(index)) {
        _preloadPlayer(index);
      }
    }

    log(
      '[PreloadManager] Updated preload window: ${desiredIndices.toList()}, current: $_currentIndex',
    );
  }

  /// Create a player for an index (without preloading)
  NativeVideoPlayer? _createPlayer(int index) {
    if (_isDisposed) return null;
    if (index < 0 || index >= _urls.length) return null;

    final playerId =
        'preload_${index}_${DateTime.now().millisecondsSinceEpoch}';

    final player = PlayerManager.instance.acquire(id: playerId);
    _indexToPlayerId[index] = playerId;
    _playerIdToIndex[playerId] = index;

    return player;
  }

  /// Preload a player for an index
  void _preloadPlayer(int index) {
    if (_isDisposed) return;
    if (_indexToPlayerId.containsKey(index)) return;

    final player = _createPlayer(index);
    if (player == null) return;

    final url = _urls[index];

    // Start preloading asynchronously
    player
        .preload(url)
        .then((_) {
          if (!_isDisposed) {
            log('[PreloadManager] Preloaded index $index');

            // Optionally warm up with muted playback
            if (config.warmupPlayback && index != _currentIndex) {
              player.setVolume(0.0);
              player.play();
              // Pause after a short buffer
              Future.delayed(const Duration(milliseconds: 500), () {
                player.pause();
              });
            }
          }
        })
        .catchError((e) {
          log('[PreloadManager] Preload failed for index $index: $e');
        });
  }

  /// Release a player for an index
  void _releasePlayer(int index) {
    final playerId = _indexToPlayerId.remove(index);
    if (playerId != null) {
      _playerIdToIndex.remove(playerId);
      PlayerManager.instance.release(playerId);
      log('[PreloadManager] Released player at index $index');
    }
  }

  /// Update URLs (e.g., for infinite scroll with new content)
  void addUrls(List<String> newUrls) {
    _urls.addAll(newUrls);
    log(
      '[PreloadManager] Added ${newUrls.length} URLs, total: ${_urls.length}',
    );
  }

  /// Dispose all managed players and clean up
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _debounceTimer?.cancel();

    // Release all managed players
    final playerIds = _indexToPlayerId.values.toList();
    for (final playerId in playerIds) {
      await PlayerManager.instance.release(playerId);
    }

    _indexToPlayerId.clear();
    _playerIdToIndex.clear();

    log('[PreloadManager] Disposed');
  }
}
