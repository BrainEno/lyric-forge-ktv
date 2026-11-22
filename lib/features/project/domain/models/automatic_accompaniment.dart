import 'audio_asset.dart';

/// Provenance of an accompaniment the app separated from the song itself
/// (D-060), kept in `AudioAsset.metadata[AutomaticAccompaniment.metadataKey]`.
///
/// Separation before recognition (D-043) always writes the mix without the
/// lead vocal next to the vocal stem. That file becomes the project's
/// accompaniment track when the project has none, so 进入 KTV can offer 纯伴奏
/// without the user finding a karaoke version first.
///
/// An `instrumentalPath` this marker does not point at was imported by the
/// user and is never replaced automatically. The marker lives apart from the
/// vocal stem marker because importing a vocal removes that one while the
/// separated accompaniment stays usable.
class AutomaticAccompaniment {
  static const String metadataKey = 'automaticAccompaniment';
  static const String automaticSource = 'auto-separation';

  final String path;
  final String? separatorRevision;
  final DateTime generatedAt;

  const AutomaticAccompaniment({
    required this.path,
    this.separatorRevision,
    required this.generatedAt,
  });

  Map<String, Object?> toJson() => {
    'source': automaticSource,
    'path': path,
    'separatorRevision': separatorRevision,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
  };

  /// The marker in [metadata], or null when absent or not ours.
  static AutomaticAccompaniment? fromAudioMetadata(
    Map<String, dynamic> metadata,
  ) {
    final raw = metadata[metadataKey];
    if (raw is! Map) return null;
    if (raw['source'] != automaticSource) return null;
    final path = raw['path'];
    final generatedAt = DateTime.tryParse('${raw['generatedAt']}');
    if (path is! String || path.trim().isEmpty || generatedAt == null) {
      return null;
    }
    final revision = raw['separatorRevision'];
    return AutomaticAccompaniment(
      path: path,
      separatorRevision: revision is String ? revision : null,
      generatedAt: generatedAt,
    );
  }
}

extension AutomaticAccompanimentAudio on AudioAsset {
  /// The accompaniment track is the one the app separated.
  bool get hasAutomaticAccompaniment {
    final path = instrumentalPath;
    if (path == null) return false;
    return AutomaticAccompaniment.fromAudioMetadata(metadata)?.path == path;
  }

  /// The accompaniment track was imported by the user.
  bool get hasUserAccompaniment =>
      instrumentalPath != null && !hasAutomaticAccompaniment;

  /// The source the project player opens with.
  ///
  /// An imported accompaniment keeps its old priority: the user brought it
  /// to sing over. A separated one can keep traces of the vocal, so the
  /// player starts on the original and 进入 KTV offers 纯伴奏.
  AudioSourceType get preferredProjectPlaybackSource =>
      hasAutomaticAccompaniment ? AudioSourceType.original : defaultSource;

  /// The metadata without the automatic accompaniment marker.
  Map<String, dynamic> get metadataWithoutAutomaticAccompaniment =>
      Map<String, dynamic>.of(metadata)
        ..remove(AutomaticAccompaniment.metadataKey);
}

/// [audio] with [path] linked as its separated accompaniment, or null when
/// nothing changes: the user imported an accompaniment of their own, or
/// [path] is already the linked automatic one.
AudioAsset? linkAutomaticAccompaniment(
  AudioAsset audio, {
  required String? path,
  String? separatorRevision,
  required DateTime generatedAt,
}) {
  if (path == null || path.trim().isEmpty) return null;
  if (audio.hasUserAccompaniment) return null;
  if (audio.instrumentalPath == path && audio.hasAutomaticAccompaniment) {
    return null;
  }
  return audio.copyWith(
    instrumentalPath: path,
    metadata: {
      ...audio.metadata,
      AutomaticAccompaniment.metadataKey: AutomaticAccompaniment(
        path: path,
        separatorRevision: separatorRevision,
        generatedAt: generatedAt,
      ).toJson(),
    },
  );
}
