import 'package:flutter/material.dart';

/// Theme configuration for the video player UI
class VideoPlayerTheme {
  /// Primary accent color (progress bar, buttons highlight)
  final Color primaryColor;

  /// Background color of the video container
  final Color backgroundColor;

  /// Semi-transparent overlay for controls
  final Color controlsBackgroundColor;

  /// Progress bar active color
  final Color progressBarColor;

  /// Buffer indicator color
  final Color bufferColor;

  /// Icon color for controls
  final Color iconColor;

  /// Icon size for control buttons
  final double iconSize;

  /// Icon size for center play/pause button
  final double centerIconSize;

  /// Text style for duration labels
  final TextStyle durationTextStyle;

  /// Text style for subtitle text
  final TextStyle subtitleTextStyle;

  /// Border radius for buttons and overlays
  final double borderRadius;

  /// Padding for the controls overlay
  final EdgeInsets controlsPadding;

  const VideoPlayerTheme({
    this.primaryColor = Colors.red,
    this.backgroundColor = Colors.black,
    this.controlsBackgroundColor = const Color(0x88000000),
    this.progressBarColor = Colors.red,
    this.bufferColor = Colors.white30,
    this.iconColor = Colors.white,
    this.iconSize = 24.0,
    this.centerIconSize = 60.0,
    this.durationTextStyle = const TextStyle(color: Colors.white, fontSize: 12),
    this.subtitleTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
    this.borderRadius = 4.0,
    this.controlsPadding = const EdgeInsets.all(16.0),
  });

  /// Create a copy with modified values
  VideoPlayerTheme copyWith({
    Color? primaryColor,
    Color? backgroundColor,
    Color? controlsBackgroundColor,
    Color? progressBarColor,
    Color? bufferColor,
    Color? iconColor,
    double? iconSize,
    double? centerIconSize,
    TextStyle? durationTextStyle,
    TextStyle? subtitleTextStyle,
    double? borderRadius,
    EdgeInsets? controlsPadding,
  }) {
    return VideoPlayerTheme(
      primaryColor: primaryColor ?? this.primaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      controlsBackgroundColor:
          controlsBackgroundColor ?? this.controlsBackgroundColor,
      progressBarColor: progressBarColor ?? this.progressBarColor,
      bufferColor: bufferColor ?? this.bufferColor,
      iconColor: iconColor ?? this.iconColor,
      iconSize: iconSize ?? this.iconSize,
      centerIconSize: centerIconSize ?? this.centerIconSize,
      durationTextStyle: durationTextStyle ?? this.durationTextStyle,
      subtitleTextStyle: subtitleTextStyle ?? this.subtitleTextStyle,
      borderRadius: borderRadius ?? this.borderRadius,
      controlsPadding: controlsPadding ?? this.controlsPadding,
    );
  }

  /// Dark theme (default) - Netflix/YouTube style
  static const dark = VideoPlayerTheme();

  /// Light theme variant
  static const light = VideoPlayerTheme(
    primaryColor: Colors.blue,
    backgroundColor: Colors.white,
    controlsBackgroundColor: Color(0xDDFFFFFF),
    progressBarColor: Colors.blue,
    bufferColor: Colors.black26,
    iconColor: Colors.black87,
    durationTextStyle: TextStyle(color: Colors.black87, fontSize: 12),
    subtitleTextStyle: TextStyle(
      color: Colors.black87,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
  );

  /// Minimal theme - less prominent controls
  static const minimal = VideoPlayerTheme(
    primaryColor: Colors.white,
    controlsBackgroundColor: Color(0x44000000),
    progressBarColor: Colors.white,
    bufferColor: Colors.white24,
    iconSize: 20.0,
    centerIconSize: 48.0,
  );
}
