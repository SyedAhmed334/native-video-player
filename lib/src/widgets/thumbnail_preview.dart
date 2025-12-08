import 'package:flutter/material.dart';
import '../models/thumbnail_config.dart';

/// Widget that displays a thumbnail preview during seek operations
class ThumbnailPreview extends StatelessWidget {
  /// Thumbnail configuration with sprite sheet info
  final ThumbnailConfig config;

  /// Current seek position to show thumbnail for
  final Duration position;

  /// Whether the preview is currently visible
  final bool isVisible;

  const ThumbnailPreview({
    super.key,
    required this.config,
    required this.position,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible || !config.isAvailable) {
      return const SizedBox.shrink();
    }

    final sourceRect = config.getSourceRect(position);

    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: config.thumbnailWidth,
        height: config.thumbnailHeight,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Image.network(
            config.spriteUrl!,
            fit: BoxFit.none,
            alignment: Alignment(
              // Calculate alignment based on source rect position
              -1 +
                  (2 *
                      sourceRect.left /
                      (config.thumbnailWidth * config.columns -
                          config.thumbnailWidth)),
              -1 +
                  (2 *
                      sourceRect.top /
                      (config.thumbnailHeight * config.rows -
                          config.thumbnailHeight)),
            ),
            width: config.thumbnailWidth * config.columns,
            height: config.thumbnailHeight * config.rows,
            errorBuilder: (context, error, stackTrace) {
              return config.placeholderWidget ??
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.white54,
                      ),
                    ),
                  );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A positioned thumbnail preview that shows above the seek bar
class SeekBarThumbnailPreview extends StatelessWidget {
  /// Thumbnail configuration
  final ThumbnailConfig config;

  /// Current seek position
  final Duration position;

  /// Total video duration
  final Duration duration;

  /// Whether seeking is active
  final bool isSeeking;

  /// The width of the seek bar
  final double seekBarWidth;

  /// Horizontal position offset (0.0 to 1.0)
  final double seekProgress;

  const SeekBarThumbnailPreview({
    super.key,
    required this.config,
    required this.position,
    required this.duration,
    required this.isSeeking,
    required this.seekBarWidth,
    required this.seekProgress,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSeeking || !config.isAvailable) {
      return const SizedBox.shrink();
    }

    // Calculate horizontal position
    final thumbWidth = config.thumbnailWidth;
    final maxOffset = seekBarWidth - thumbWidth;
    final xOffset = (seekProgress * seekBarWidth - thumbWidth / 2).clamp(
      0.0,
      maxOffset,
    );

    return Positioned(
      left: xOffset,
      bottom: 50, // Above the seek bar
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThumbnailPreview(
            config: config,
            position: position,
            isVisible: isSeeking,
          ),
          const SizedBox(height: 4),
          // Time indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _formatDuration(position),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration dur) {
    final hours = dur.inHours;
    final minutes = dur.inMinutes.remainder(60);
    final seconds = dur.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
