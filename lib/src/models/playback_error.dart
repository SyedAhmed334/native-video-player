/// Types of playback errors for error recovery
enum PlaybackErrorType {
  /// Network-related error (no connection, timeout)
  network,

  /// Server returned an error (404, 500, etc.)
  server,

  /// Video format not supported
  format,

  /// DRM license error
  drm,

  /// Source not found or invalid URL
  source,

  /// Decoder/renderer error
  decoder,

  /// Unknown error
  unknown,
}

/// Playback error with categorization and recovery hints
class PlaybackError {
  /// Error code from native layer
  final String code;

  /// Human-readable error message
  final String message;

  /// Categorized error type
  final PlaybackErrorType type;

  /// Whether this error can be recovered by retrying
  final bool isRecoverable;

  /// Timestamp when error occurred
  final DateTime timestamp;

  const PlaybackError({
    required this.code,
    required this.message,
    required this.type,
    this.isRecoverable = true,
    required this.timestamp,
  });

  /// Create error from native error message
  factory PlaybackError.fromNative(String errorMessage) {
    final type = _categorizeError(errorMessage);
    final isRecoverable = _isRecoverable(type);

    return PlaybackError(
      code: _extractCode(errorMessage),
      message: _cleanMessage(errorMessage),
      type: type,
      isRecoverable: isRecoverable,
      timestamp: DateTime.now(),
    );
  }

  /// Categorize error based on message content
  static PlaybackErrorType _categorizeError(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('timeout') ||
        lower.contains('unreachable') ||
        lower.contains('no internet')) {
      return PlaybackErrorType.network;
    }

    if (lower.contains('404') ||
        lower.contains('500') ||
        lower.contains('server') ||
        lower.contains('http')) {
      return PlaybackErrorType.server;
    }

    if (lower.contains('format') ||
        lower.contains('codec') ||
        lower.contains('unsupported')) {
      return PlaybackErrorType.format;
    }

    if (lower.contains('drm') ||
        lower.contains('license') ||
        lower.contains('widevine') ||
        lower.contains('fairplay')) {
      return PlaybackErrorType.drm;
    }

    if (lower.contains('source') ||
        lower.contains('url') ||
        lower.contains('not found')) {
      return PlaybackErrorType.source;
    }

    if (lower.contains('decoder') ||
        lower.contains('renderer') ||
        lower.contains('render')) {
      return PlaybackErrorType.decoder;
    }

    return PlaybackErrorType.unknown;
  }

  /// Determine if error type is recoverable
  static bool _isRecoverable(PlaybackErrorType type) {
    switch (type) {
      case PlaybackErrorType.network:
      case PlaybackErrorType.server:
      case PlaybackErrorType.drm:
        return true;
      case PlaybackErrorType.format:
      case PlaybackErrorType.source:
      case PlaybackErrorType.decoder:
        return false;
      case PlaybackErrorType.unknown:
        return true;
    }
  }

  /// Extract error code from message
  static String _extractCode(String message) {
    final regex = RegExp(r'\b\d{3}\b');
    final match = regex.firstMatch(message);
    return match?.group(0) ?? 'ERR';
  }

  /// Clean up error message for display
  static String _cleanMessage(String message) {
    // Remove prefix like "Error: " or "Failed to initialize: "
    var clean = message.replaceFirst(
      RegExp(r'^(Error|Failed)[:\s]+', caseSensitive: false),
      '',
    );

    // Truncate if too long
    if (clean.length > 100) {
      clean = '${clean.substring(0, 97)}...';
    }

    return clean;
  }

  /// Get user-friendly message based on error type
  String get userMessage {
    switch (type) {
      case PlaybackErrorType.network:
        return 'Network connection lost. Tap to retry.';
      case PlaybackErrorType.server:
        return 'Server error. Tap to retry.';
      case PlaybackErrorType.format:
        return 'Video format not supported.';
      case PlaybackErrorType.drm:
        return 'License error. Tap to retry.';
      case PlaybackErrorType.source:
        return 'Video not available.';
      case PlaybackErrorType.decoder:
        return 'Playback error.';
      case PlaybackErrorType.unknown:
        return 'Something went wrong. Tap to retry.';
    }
  }

  /// Get icon for error type
  String get iconName {
    switch (type) {
      case PlaybackErrorType.network:
        return 'wifi_off';
      case PlaybackErrorType.server:
        return 'cloud_off';
      case PlaybackErrorType.drm:
        return 'lock';
      default:
        return 'error_outline';
    }
  }

  Map<String, dynamic> toMap() => {
    'code': code,
    'message': message,
    'type': type.name,
    'isRecoverable': isRecoverable,
    'timestamp': timestamp.toIso8601String(),
  };
}
