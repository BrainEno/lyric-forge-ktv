class AudioAsset {
  final String originalPath;
  final String? normalizedPath;
  final String? vocalPath;
  final String? instrumentalPath;
  final String? thumbnailPath;
  final String format;
  final int? sampleRate;
  final int? bitDepth;
  final Duration? duration;
  final Map<String, dynamic> metadata;

  const AudioAsset({
    required this.originalPath,
    this.normalizedPath,
    this.vocalPath,
    this.instrumentalPath,
    this.thumbnailPath,
    required this.format,
    this.sampleRate,
    this.bitDepth,
    this.duration,
    this.metadata = const {},
  });

  AudioAsset copyWith({
    String? originalPath,
    String? normalizedPath,
    String? vocalPath,
    String? instrumentalPath,
    String? thumbnailPath,
    String? format,
    int? sampleRate,
    int? bitDepth,
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    return AudioAsset(
      originalPath: originalPath ?? this.originalPath,
      normalizedPath: normalizedPath ?? this.normalizedPath,
      vocalPath: vocalPath ?? this.vocalPath,
      instrumentalPath: instrumentalPath ?? this.instrumentalPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      format: format ?? this.format,
      sampleRate: sampleRate ?? this.sampleRate,
      bitDepth: bitDepth ?? this.bitDepth,
      duration: duration ?? this.duration,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'originalPath': originalPath,
      'normalizedPath': normalizedPath,
      'vocalPath': vocalPath,
      'instrumentalPath': instrumentalPath,
      'thumbnailPath': thumbnailPath,
      'format': format,
      'sampleRate': sampleRate,
      'bitDepth': bitDepth,
      'duration': duration?.inMilliseconds,
      'metadata': metadata,
    };
  }

  factory AudioAsset.fromJson(Map<String, dynamic> json) {
    return AudioAsset(
      originalPath: json['originalPath'] as String,
      normalizedPath: json['normalizedPath'] as String?,
      vocalPath: json['vocalPath'] as String?,
      instrumentalPath: json['instrumentalPath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      format: json['format'] as String,
      sampleRate: json['sampleRate'] as int?,
      bitDepth: json['bitDepth'] as int?,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }
}
