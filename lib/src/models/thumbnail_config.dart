import 'package:flutter/material.dart';

/// Configuration for thumbnail preview during seek
class ThumbnailConfig {
  /// URL to the sprite sheet image containing all thumbnails
  final String? spriteUrl;

  /// Optional VTT file URL for thumbnail timing data
  final String? vttUrl;

  /// Number of columns in the sprite sheet
  final int columns;

  /// Number of rows in the sprite sheet
  final int rows;

  /// Width of each thumbnail in pixels
  final double thumbnailWidth;

  /// Height of each thumbnail in pixels
  final double thumbnailHeight;

  /// Interval between each thumbnail
  final Duration interval;

  /// Total duration of the video (required to calculate positions)
  final Duration? videoDuration;

  /// Widget to show when no thumbnail is available
  final Widget? placeholderWidget;

  const ThumbnailConfig({
    this.spriteUrl,
    this.vttUrl,
    this.columns = 10,
    this.rows = 10,
    this.thumbnailWidth = 160,
    this.thumbnailHeight = 90,
    this.interval = const Duration(seconds: 10),
    this.videoDuration,
    this.placeholderWidget,
  });

  /// Check if thumbnail preview is available
  bool get isAvailable => spriteUrl != null && spriteUrl!.isNotEmpty;

  /// Total number of thumbnails in the sprite sheet
  int get totalThumbnails => columns * rows;

  /// Get the thumbnail index for a given position
  int getThumbnailIndex(Duration position) {
    if (interval.inMilliseconds == 0) return 0;
    final index = position.inMilliseconds ~/ interval.inMilliseconds;
    return index.clamp(0, totalThumbnails - 1);
  }

  /// Get the sprite offset for a given thumbnail index
  Offset getSpriteOffset(int index) {
    final col = index % columns;
    final row = index ~/ columns;
    return Offset(col * thumbnailWidth, row * thumbnailHeight);
  }

  /// Get the source rect for a given position
  Rect getSourceRect(Duration position) {
    final index = getThumbnailIndex(position);
    final offset = getSpriteOffset(index);
    return Rect.fromLTWH(offset.dx, offset.dy, thumbnailWidth, thumbnailHeight);
  }
}
