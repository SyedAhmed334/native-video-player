/// Cast framework type
enum CastFramework {
  /// Google Chromecast (Android, Chrome)
  chromecast,

  /// Apple AirPlay (iOS, macOS)
  airplay,
}

/// State of the cast session
enum CastState {
  /// No cast session
  notConnected,

  /// Connecting to cast device
  connecting,

  /// Connected and ready
  connected,

  /// Connected and playing
  playing,

  /// Connected but paused
  paused,

  /// Buffering on cast device
  buffering,

  /// Disconnecting
  disconnecting,
}

/// Information about a cast device
class CastDevice {
  /// Unique device identifier
  final String id;

  /// Display name of the device
  final String name;

  /// Type of cast framework
  final CastFramework framework;

  /// Model name (e.g., "Chromecast Ultra", "Apple TV 4K")
  final String? model;

  const CastDevice({
    required this.id,
    required this.name,
    required this.framework,
    this.model,
  });

  factory CastDevice.fromMap(Map<String, dynamic> map) {
    return CastDevice(
      id: map['id'] as String,
      name: map['name'] as String,
      framework: map['framework'] == 'airplay'
          ? CastFramework.airplay
          : CastFramework.chromecast,
      model: map['model'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'framework': framework.name,
      if (model != null) 'model': model,
    };
  }
}

/// Configuration for cast functionality
class CastConfig {
  /// Whether cast button should be shown
  final bool showCastButton;

  /// Chromecast receiver app ID (null for default media receiver)
  final String? receiverAppId;

  /// Custom CSS style name for web receiver
  final String? customReceiverStyle;

  /// Whether to auto-connect to last used device
  final bool autoConnect;

  /// Whether to pause local playback when casting starts
  final bool pauseLocalOnCastStart;

  const CastConfig({
    this.showCastButton = true,
    this.receiverAppId,
    this.customReceiverStyle,
    this.autoConnect = false,
    this.pauseLocalOnCastStart = true,
  });

  /// Default cast configuration
  static const defaultConfig = CastConfig();

  /// Cast config with custom receiver app
  factory CastConfig.withReceiver({
    required String receiverAppId,
    String? customReceiverStyle,
  }) {
    return CastConfig(
      receiverAppId: receiverAppId,
      customReceiverStyle: customReceiverStyle,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'showCastButton': showCastButton,
      if (receiverAppId != null) 'receiverAppId': receiverAppId,
      if (customReceiverStyle != null)
        'customReceiverStyle': customReceiverStyle,
      'autoConnect': autoConnect,
      'pauseLocalOnCastStart': pauseLocalOnCastStart,
    };
  }
}

/// Callback for cast state changes
typedef CastStateCallback = void Function(CastState state, CastDevice? device);

/// Callback for cast device discovery
typedef CastDevicesCallback = void Function(List<CastDevice> devices);
