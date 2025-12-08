import 'dart:developer';
import 'services/native_video_player_service.dart';

/// Singleton manager for video player instances
/// Manages a pool of players for efficient resource usage
class PlayerManager {
  static final PlayerManager _instance = PlayerManager._internal();

  /// Get the singleton instance
  static PlayerManager get instance => _instance;

  PlayerManager._internal();

  /// Active player instances
  final Map<String, NativeVideoPlayer> _players = {};

  /// Maximum number of simultaneous players
  int _maxPoolSize = 3;

  /// Get all active player IDs
  List<String> get activePlayerIds => _players.keys.toList();

  /// Get number of active players
  int get activePlayerCount => _players.length;

  /// Set maximum pool size
  void setPoolSize(int size) {
    if (size < 1) {
      throw ArgumentError('Pool size must be at least 1');
    }
    _maxPoolSize = size;
    _enforcePoolLimit();
  }

  /// Acquire a player instance
  /// If [id] is provided, uses that ID; otherwise generates a unique one
  /// Returns existing player if ID already exists
  NativeVideoPlayer acquire({String? id}) {
    final playerId = id ?? _generateId();

    // Return existing player if it exists
    if (_players.containsKey(playerId)) {
      log('[PlayerManager] Returning existing player: $playerId');
      return _players[playerId]!;
    }

    // Enforce pool limit before creating new player
    _enforcePoolLimit();

    // Create new player
    final player = NativeVideoPlayer.create(id: playerId);
    _players[playerId] = player;
    log(
      '[PlayerManager] Created new player: $playerId (total: ${_players.length})',
    );

    return player;
  }

  /// Get an existing player by ID
  NativeVideoPlayer? get(String id) {
    return _players[id];
  }

  /// Release a specific player
  Future<void> release(String id) async {
    final player = _players.remove(id);
    if (player != null) {
      await player.dispose();
      log(
        '[PlayerManager] Released player: $id (remaining: ${_players.length})',
      );
    }
  }

  /// Dispose of the oldest player to make room if at capacity
  void _enforcePoolLimit() {
    while (_players.length >= _maxPoolSize) {
      final oldestId = _players.keys.first;
      log('[PlayerManager] Pool full, releasing oldest: $oldestId');
      _players.remove(oldestId)?.dispose();
    }
  }

  /// Dispose all players
  Future<void> disposeAll() async {
    log('[PlayerManager] Disposing all players (${_players.length})');
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }

  /// Pause all players (useful for app lifecycle)
  Future<void> pauseAll() async {
    for (final player in _players.values) {
      if (player.isPlaying) {
        await player.pause();
      }
    }
  }

  /// Generate unique player ID
  String _generateId() {
    return 'player_${DateTime.now().millisecondsSinceEpoch}_${_players.length}';
  }

  /// Called when app enters background
  /// Pauses all players and releases texture resources to reduce memory
  Future<void> onAppPaused() async {
    log('[PlayerManager] App paused - pausing all players');
    await pauseAll();
  }

  /// Called when app returns to foreground
  /// Players resume based on their previous state
  Future<void> onAppResumed() async {
    log('[PlayerManager] App resumed');
    // Players will resume based on individual state when visible
  }

  /// Called when system memory warning is received
  /// Aggressively releases players to free memory
  Future<void> onMemoryWarning() async {
    log('[PlayerManager] Memory warning - releasing inactive players');

    // Keep only one player (ideally the currently visible one)
    while (_players.length > 1) {
      final oldestId = _players.keys.first;
      await release(oldestId);
    }
  }

  /// Clear cached data across all players
  Future<void> clearCache() async {
    log('[PlayerManager] Clearing cache');
    await NativeVideoPlayer.clearCache();
  }

  /// Get current cache size in bytes
  Future<int> getCacheSize() async {
    return await NativeVideoPlayer.getCacheSize();
  }
}
