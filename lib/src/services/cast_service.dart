import 'dart:async';
import 'package:flutter/services.dart';
import '../models/cast_config.dart';

/// Service for Chromecast and AirPlay functionality
class CastService {
  static const MethodChannel _channel = MethodChannel('native_video_player');

  // Cast state
  bool _isInitialized = false;
  bool _isCasting = false;
  CastState _state = CastState.notConnected;
  CastDevice? _connectedDevice;

  // Callbacks
  CastStateCallback? onCastStateChanged;
  CastDevicesCallback? onDevicesDiscovered;

  /// Initialize Cast SDK
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final result = await _channel.invokeMethod('initCast');
      _isInitialized = result == true;
      return _isInitialized;
    } catch (e) {
      print('[CastService] Init error: $e');
      return false;
    }
  }

  /// Get available cast devices
  Future<List<CastDevice>> getDevices() async {
    if (!_isInitialized) await initialize();

    try {
      final result = await _channel.invokeMethod('getCastDevices');
      final devices = (result as List)
          .map((d) => CastDevice(
                id: d['id'] as String,
                name: d['name'] as String,
                framework: CastFramework.chromecast,
                model: d['description'] as String?,
              ))
          .toList();

      onDevicesDiscovered?.call(devices);
      return devices;
    } catch (e) {
      print('[CastService] getDevices error: $e');
      return [];
    }
  }

  /// Connect to a cast device
  Future<bool> castTo(CastDevice device) async {
    try {
      final result =
          await _channel.invokeMethod('castTo', {'deviceId': device.id});
      if (result == true) {
        _isCasting = true;
        _connectedDevice = device;
        _state = CastState.connecting;
        onCastStateChanged?.call(_state, device);
      }
      return result == true;
    } catch (e) {
      print('[CastService] castTo error: $e');
      return false;
    }
  }

  /// Load media on cast device
  Future<bool> loadMedia({
    required String url,
    String? title,
    Duration startPosition = Duration.zero,
  }) async {
    try {
      final result = await _channel.invokeMethod('castMedia', {
        'url': url,
        'title': title,
        'position': startPosition.inMilliseconds,
      });
      return result == true;
    } catch (e) {
      print('[CastService] loadMedia error: $e');
      return false;
    }
  }

  /// Control remote playback
  Future<void> play() async {
    await _channel.invokeMethod('castPlay');
  }

  Future<void> pause() async {
    await _channel.invokeMethod('castPause');
  }

  Future<void> seekTo(Duration position) async {
    await _channel
        .invokeMethod('castSeek', {'position': position.inMilliseconds});
  }

  Future<void> stop() async {
    await _channel.invokeMethod('castStop');
  }

  /// Disconnect from cast device
  Future<void> disconnect() async {
    await _channel.invokeMethod('castDisconnect');
    _isCasting = false;
    _connectedDevice = null;
    _state = CastState.notConnected;
    onCastStateChanged?.call(_state, null);
  }

  /// Get current cast state
  Future<CastState> getCastState() async {
    try {
      final result = await _channel.invokeMethod('getCastState');
      switch (result) {
        case 'connected':
          return CastState.connected;
        case 'connecting':
          return CastState.connecting;
        case 'playing':
          return CastState.playing;
        case 'paused':
          return CastState.paused;
        default:
          return CastState.notConnected;
      }
    } catch (e) {
      return CastState.notConnected;
    }
  }

  /// Check if currently casting
  Future<bool> isCasting() async {
    try {
      return await _channel.invokeMethod('isCasting') == true;
    } catch (e) {
      return false;
    }
  }

  /// Get connected device
  CastDevice? get connectedDevice => _connectedDevice;

  /// Get current state
  CastState get state => _state;

  /// Check if currently casting (local state)
  bool get isCastingNow => _isCasting;

  /// Check if initialized
  bool get isInitialized => _isInitialized;
}
