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

/// 音频源类型
enum AudioSourceType {
  original, // 原声
  instrumental, // 伴奏
  vocals, // 人声
}

/// AudioAsset 扩展方法
extension AudioAssetExtensions on AudioAsset {
  /// 获取指定音源的路径
  String? getPathForSource(AudioSourceType source) => switch (source) {
        AudioSourceType.original => originalPath,
        AudioSourceType.instrumental => instrumentalPath,
        AudioSourceType.vocals => vocalPath,
      };

  /// 检查音源是否可用
  bool hasSource(AudioSourceType source) => getPathForSource(source) != null;

  /// 获取默认音源（优先级：伴奏 > 原声 > 人声）
  /// 注意：originalPath 是必填字段，所以 original 总是可用
  AudioSourceType get defaultSource {
    if (instrumentalPath != null) return AudioSourceType.instrumental;
    if (vocalPath != null) return AudioSourceType.vocals;
    return AudioSourceType.original;
  }

  /// 获取所有可用音源列表
  List<AudioSourceType> get availableSources {
    return AudioSourceType.values.where(hasSource).toList();
  }
}
