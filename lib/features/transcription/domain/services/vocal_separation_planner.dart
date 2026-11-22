import '../../../project/domain/models/audio_asset.dart';
import '../models/vocal_separation_models.dart';

enum VocalSeparationAction { run, reuse, skip }

class VocalSeparationPlan {
  final VocalSeparationAction action;
  final VocalSeparationSkipReason? skipReason;

  /// The automatic stem to reuse when [action] is [VocalSeparationAction.reuse].
  final VocalStemMarker? reusable;

  const VocalSeparationPlan.run()
    : action = VocalSeparationAction.run,
      skipReason = null,
      reusable = null;

  const VocalSeparationPlan.reuse(VocalStemMarker marker)
    : action = VocalSeparationAction.reuse,
      skipReason = null,
      reusable = marker;

  const VocalSeparationPlan.skip(VocalSeparationSkipReason reason)
    : action = VocalSeparationAction.skip,
      skipReason = reason,
      reusable = null;
}

/// Facts about the song file the planner needs; gathered by the caller so the
/// decision itself stays free of I/O.
class VocalSeparationFacts {
  final bool sourceExists;
  final int sourceBytes;
  final DateTime? sourceModified;

  /// Whether `AudioAsset.vocalPath` points at an existing file.
  final bool vocalFileExists;

  /// Whether the automatic stem's accompaniment, if any, still exists.
  final bool accompanimentFileExists;

  const VocalSeparationFacts({
    required this.sourceExists,
    required this.sourceBytes,
    required this.sourceModified,
    required this.vocalFileExists,
    this.accompanimentFileExists = false,
  });
}

/// Decides whether a recognition run separates, reuses a stem or skips.
///
/// Order matters and is pinned by tests:
/// 1. the user's choice ([VocalSeparationPreference.off]);
/// 2. a vocal stem the user imported is never second-guessed;
/// 3. platform support, source availability and length;
/// 4. an automatic stem is reused only while both the song file (size and
///    modification time) and the separator revision are unchanged, and,
///    when the caller needs the accompaniment (D-060), while that file is
///    still there.
class VocalSeparationPlanner {
  /// Separation memory grows with length (four stems of float stereo); songs
  /// longer than this are recognised from the mix.
  static const Duration maxDuration = Duration(minutes: 15);

  const VocalSeparationPlanner();

  VocalSeparationPlan plan({
    required AudioAsset audio,
    required VocalSeparationPreference preference,
    required bool platformSupported,
    required String separatorRevision,
    required VocalSeparationFacts facts,
    bool requireAccompaniment = false,
  }) {
    if (preference == VocalSeparationPreference.off) {
      return const VocalSeparationPlan.skip(VocalSeparationSkipReason.disabled);
    }
    final marker = VocalStemMarker.fromAudioMetadata(audio.metadata);
    final vocalPath = audio.vocalPath?.trim() ?? '';
    final automaticStem = marker != null && marker.vocalPath == vocalPath;
    if (vocalPath.isNotEmpty && facts.vocalFileExists && !automaticStem) {
      return const VocalSeparationPlan.skip(
        VocalSeparationSkipReason.userProvidedVocal,
      );
    }
    if (!platformSupported) {
      return const VocalSeparationPlan.skip(
        VocalSeparationSkipReason.unsupportedPlatform,
      );
    }
    if (!facts.sourceExists) {
      return const VocalSeparationPlan.skip(
        VocalSeparationSkipReason.sourceMissing,
      );
    }
    final duration = audio.duration;
    if (duration != null && duration > maxDuration) {
      return const VocalSeparationPlan.skip(VocalSeparationSkipReason.tooLong);
    }
    if (marker != null &&
        automaticStem &&
        facts.vocalFileExists &&
        (!requireAccompaniment || facts.accompanimentFileExists) &&
        marker.separatorRevision == separatorRevision &&
        marker.sourceFingerprint == fingerprintOf(audio.originalPath, facts)) {
      return VocalSeparationPlan.reuse(marker);
    }
    return const VocalSeparationPlan.run();
  }

  /// Identity of the song file a stem was made from. Size plus modification
  /// time catches a replaced or re-encoded file without hashing the song.
  static String fingerprintOf(String path, VocalSeparationFacts facts) {
    final modified = facts.sourceModified?.toUtc().millisecondsSinceEpoch ?? 0;
    return '${facts.sourceBytes}:$modified:$path';
  }
}
