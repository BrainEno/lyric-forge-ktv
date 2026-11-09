import '../../../project/domain/models/audio_asset.dart';

/// Chooses an updated project asset only when it cannot change the audio that
/// is currently playing. A caller must additionally verify the active project
/// in the playback session; this guard compares audio paths, not project IDs.
AudioAsset? safeProjectAudioSourceUpdate({
  required AudioAsset? current,
  required AudioAsset expected,
  required AudioAsset replacement,
  required AudioSourceType? activeSource,
}) {
  if (current == null || activeSource == null) return null;
  if (current.originalPath != expected.originalPath ||
      current.vocalPath != expected.vocalPath ||
      current.instrumentalPath != expected.instrumentalPath ||
      replacement.originalPath != expected.originalPath) {
    return null;
  }
  final playingPath = current.getPathForSource(activeSource);
  if (playingPath == null ||
      playingPath != replacement.getPathForSource(activeSource)) {
    return null;
  }
  return replacement;
}

/// Optional capability for updating inactive project source paths without
/// loading, seeking, playing or pausing audio. Session/project identity must be
/// checked by the caller before invoking it. Returns false when stale, remote,
/// loading or when the replacement would change the active source.
abstract interface class ActiveProjectAudioSourceUpdater {
  bool updateActiveProjectAudioSources({
    required AudioAsset expected,
    required AudioAsset replacement,
  });
}
