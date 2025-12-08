/// DRM type for protected content
enum DrmType {
  /// Google Widevine DRM (Android, Chrome, ChromeOS)
  widevine,

  /// Apple FairPlay Streaming DRM (iOS, macOS, Safari)
  fairPlay,

  /// Microsoft PlayReady DRM (Windows, Xbox)
  playReady,

  /// ClearKey DRM (open standard, testing)
  clearKey,
}

/// DRM configuration for protected video content
class DrmConfig {
  /// Type of DRM system to use
  final DrmType type;

  /// License server URL for acquiring content keys
  final String licenseUrl;

  /// Optional: Certificate URL (required for FairPlay)
  final String? certificateUrl;

  /// Optional: Headers to send with license requests
  final Map<String, String>? headers;

  /// Optional: Custom license request data
  final Map<String, dynamic>? customData;

  /// Whether to persist the license offline
  final bool persistLicense;

  /// Optional: Maximum license duration in seconds
  final int? maxLicenseDurationSeconds;

  const DrmConfig({
    required this.type,
    required this.licenseUrl,
    this.certificateUrl,
    this.headers,
    this.customData,
    this.persistLicense = false,
    this.maxLicenseDurationSeconds,
  });

  /// Create a Widevine DRM configuration
  factory DrmConfig.widevine({
    required String licenseUrl,
    Map<String, String>? headers,
    bool persistLicense = false,
  }) {
    return DrmConfig(
      type: DrmType.widevine,
      licenseUrl: licenseUrl,
      headers: headers,
      persistLicense: persistLicense,
    );
  }

  /// Create a FairPlay DRM configuration
  /// Note: FairPlay requires a certificate URL
  factory DrmConfig.fairPlay({
    required String licenseUrl,
    required String certificateUrl,
    Map<String, String>? headers,
    bool persistLicense = false,
  }) {
    return DrmConfig(
      type: DrmType.fairPlay,
      licenseUrl: licenseUrl,
      certificateUrl: certificateUrl,
      headers: headers,
      persistLicense: persistLicense,
    );
  }

  /// Create a ClearKey DRM configuration (for testing)
  factory DrmConfig.clearKey({
    required String licenseUrl,
    Map<String, String>? headers,
  }) {
    return DrmConfig(
      type: DrmType.clearKey,
      licenseUrl: licenseUrl,
      headers: headers,
    );
  }

  /// Convert to Map for native communication
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'licenseUrl': licenseUrl,
      if (certificateUrl != null) 'certificateUrl': certificateUrl,
      if (headers != null) 'headers': headers,
      if (customData != null) 'customData': customData,
      'persistLicense': persistLicense,
      if (maxLicenseDurationSeconds != null)
        'maxLicenseDurationSeconds': maxLicenseDurationSeconds,
    };
  }

  /// Check if this is a valid FairPlay configuration
  bool get isValidFairPlay =>
      type == DrmType.fairPlay &&
      certificateUrl != null &&
      certificateUrl!.isNotEmpty;

  /// Check if offline playback is enabled
  bool get isOfflineEnabled => persistLicense;
}

/// Callback for handling DRM license errors
typedef DrmErrorCallback = void Function(String code, String message);

/// Callback for handling DRM key status changes
typedef DrmKeyStatusCallback = void Function(String keyId, String status);
