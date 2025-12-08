/// Represents a video quality option
class VideoQuality {
  final int index;
  final int width;
  final int height;
  final int bitrate;
  final String label;

  VideoQuality({
    required this.index,
    required this.width,
    required this.height,
    required this.bitrate,
    required this.label,
  });

  factory VideoQuality.fromMap(Map<dynamic, dynamic> map) {
    return VideoQuality(
      index: map['index'] as int,
      width: map['width'] as int,
      height: map['height'] as int,
      bitrate: map['bitrate'] as int,
      label: map['label'] as String,
    );
  }

  @override
  String toString() => '$label (${width}x$height)';
}

/// Represents an audio track option
class AudioTrack {
  final int index;
  final String language;
  final String label;

  AudioTrack({
    required this.index,
    required this.language,
    required this.label,
  });

  factory AudioTrack.fromMap(Map<dynamic, dynamic> map) {
    return AudioTrack(
      index: map['index'] as int,
      language: map['language'] as String,
      label: map['label'] as String,
    );
  }

  @override
  String toString() => label;
}

/// Represents a subtitle track option
class SubtitleTrack {
  final int index;
  final String language;
  final String label;

  SubtitleTrack({
    required this.index,
    required this.language,
    required this.label,
  });

  factory SubtitleTrack.fromMap(Map<dynamic, dynamic> map) {
    return SubtitleTrack(
      index: map['index'] as int,
      language: map['language'] as String,
      label: map['label'] as String,
    );
  }

  @override
  String toString() => label;
}
