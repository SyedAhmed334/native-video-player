import 'package:flutter/material.dart';
import '../models/playback_error.dart';

/// Error overlay widget for video player
/// Shows error message with retry option
class ErrorOverlay extends StatelessWidget {
  /// The playback error to display
  final PlaybackError? error;

  /// Callback when user taps retry
  final VoidCallback? onRetry;

  /// Callback when user taps dismiss (for non-recoverable errors)
  final VoidCallback? onDismiss;

  const ErrorOverlay({
    super.key,
    required this.error,
    this.onRetry,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();

    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error icon
              Icon(_getIcon(error!.type), color: Colors.white70, size: 48),
              const SizedBox(height: 16),

              // User-friendly message
              Text(
                error!.userMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),

              // Retry button (if recoverable)
              if (error!.isRecoverable)
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: onDismiss,
                  child: const Text(
                    'Dismiss',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIcon(PlaybackErrorType type) {
    switch (type) {
      case PlaybackErrorType.network:
        return Icons.wifi_off;
      case PlaybackErrorType.server:
        return Icons.cloud_off;
      case PlaybackErrorType.drm:
        return Icons.lock;
      case PlaybackErrorType.format:
        return Icons.videocam_off;
      case PlaybackErrorType.source:
        return Icons.broken_image;
      case PlaybackErrorType.decoder:
        return Icons.error_outline;
      case PlaybackErrorType.unknown:
        return Icons.warning_amber;
    }
  }
}

/// Minimal buffer health indicator
class BufferHealthIndicator extends StatelessWidget {
  /// Buffer health value (0.0 to 1.0)
  final double health;

  /// Whether to show the indicator
  final bool isVisible;

  /// Width of the indicator
  final double width;

  /// Height of the indicator
  final double height;

  const BufferHealthIndicator({
    super.key,
    required this.health,
    this.isVisible = true,
    this.width = 60,
    this.height = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: health.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: _getColor(health),
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }

  Color _getColor(double health) {
    if (health < 0.2) return Colors.red;
    if (health < 0.5) return Colors.orange;
    return Colors.green;
  }
}
