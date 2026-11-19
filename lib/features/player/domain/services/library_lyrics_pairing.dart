import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../models/local_media_metadata.dart';
import 'library_lyric_file_matcher.dart';

/// What the library remembers about lyrics it paired on its own (D-034).
///
/// Pairing by file name is a guess. The record, kept in the song's local
/// metadata next to `linkedProjectId`, lets the library say which songs got
/// their lyrics that way and lets the user take a wrong guess back: it holds
/// the file, the project and enough of the project's state before the
/// pairing to undo it without touching anything the user changed since.
class LibraryLyricsPairing {
  const LibraryLyricsPairing({
    required this.lyricPath,
    required this.projectId,
    required this.reason,
    required this.createdProject,
    required this.projectRevision,
    required this.previousStatus,
    required this.previousStage,
    required this.fingerprint,
    required this.pairedAt,
  });

  /// Key of the record in [LocalMediaMetadata.metadata].
  static const String metadataKey = 'lyricAutoLink';

  /// Key of the lyric files the user unpaired from the song; they are not
  /// paired with it again.
  static const String dismissedKey = 'lyricAutoLinkDismissed';

  /// The lyric file that was imported.
  final String lyricPath;

  /// The project the file was imported into.
  final String projectId;

  /// Why the file was thought to belong to the song.
  final LibraryLyricMatchReason reason;

  /// Whether the pairing created [projectId] rather than filling an empty
  /// project the song already had.
  final bool createdProject;

  /// The project's revision right after the pairing saved it.
  final int projectRevision;

  /// The project's status and stage before the lyrics went in.
  final ProjectStatus previousStatus;
  final ProcessingStage previousStage;

  /// [lyricLinesFingerprint] of the imported lyrics, to tell whether anyone
  /// edited them since.
  final String fingerprint;

  final DateTime pairedAt;

  /// The record in [metadata], or null when the song's lyrics were not
  /// paired automatically. A record left behind after the song was linked to
  /// another project (by hand, or by playback healing the link) is ignored.
  static LibraryLyricsPairing? of(LocalMediaMetadata? metadata) {
    if (metadata == null) return null;
    final pairing = fromJson(metadata.metadata[metadataKey]);
    final linked = metadata.metadata['linkedProjectId'];
    if (pairing == null || linked is! String) return null;
    return linked.trim() == pairing.projectId ? pairing : null;
  }

  /// The lyric files the user unpaired from the song described by
  /// [metadata].
  static Set<String> dismissedFiles(LocalMediaMetadata? metadata) {
    final raw = metadata?.metadata[dismissedKey];
    if (raw is! List) return const {};
    return {
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item,
    };
  }

  Map<String, Object?> toJson() => {
    'path': lyricPath,
    'projectId': projectId,
    'reason': reason.name,
    'createdProject': createdProject,
    'projectRevision': projectRevision,
    'previousStatus': previousStatus.name,
    'previousStage': previousStage.name,
    'fingerprint': fingerprint,
    'pairedAt': pairedAt.toIso8601String(),
  };

  /// Reads a record written by [toJson]; null for anything malformed, so a
  /// damaged record only hides the marker instead of breaking the library.
  static LibraryLyricsPairing? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final projectId = raw['projectId'];
    final revision = raw['projectRevision'];
    final fingerprint = raw['fingerprint'];
    final pairedAt = DateTime.tryParse('${raw['pairedAt']}');
    final reason = _byName(LibraryLyricMatchReason.values, raw['reason']);
    final status = _byName(ProjectStatus.values, raw['previousStatus']);
    final stage = _byName(ProcessingStage.values, raw['previousStage']);
    if (path is! String ||
        path.trim().isEmpty ||
        projectId is! String ||
        projectId.trim().isEmpty ||
        revision is! int ||
        fingerprint is! String ||
        pairedAt == null ||
        reason == null ||
        status == null ||
        stage == null) {
      return null;
    }
    return LibraryLyricsPairing(
      lyricPath: path,
      projectId: projectId,
      reason: reason,
      createdProject: raw['createdProject'] == true,
      projectRevision: revision,
      previousStatus: status,
      previousStage: stage,
      fingerprint: fingerprint,
      pairedAt: pairedAt,
    );
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// [project] without the lyrics [pairing] put into it: no lyric document,
/// the status and stage it had before, and no record of the import. Other
/// details, including backups of older lyrics, are kept.
ProjectManifest projectWithoutPairedLyrics(
  ProjectManifest project,
  LibraryLyricsPairing pairing,
) {
  final metadata = {...project.metadata};
  final import = metadata['lyricImport'];
  if (import is Map && import['path'] == pairing.lyricPath) {
    metadata.remove('lyricImport');
    metadata.remove('lyricSource');
  }
  return ProjectManifest(
    id: project.id,
    name: project.name,
    artist: project.artist,
    album: project.album,
    createdAt: project.createdAt,
    updatedAt: project.updatedAt,
    revision: project.revision,
    status: pairing.previousStatus,
    currentStage: pairing.previousStage,
    audioAsset: project.audioAsset,
    projectDirectory: project.projectDirectory,
    metadata: metadata,
  );
}

/// A short, stable digest of the text and timing of [document]'s lines.
///
/// Used only to notice that lyrics changed after they were paired: the
/// editor saves other project details too (review marks, view state), and
/// those must not make the user's unchanged lyrics look edited. Returns an
/// empty string for a project without lyrics.
String lyricLinesFingerprint(LyricDocument? document) {
  final lines = document?.lines ?? const <LyricLine>[];
  if (lines.isEmpty) return '';
  // 32-bit FNV-1a over the UTF-16 code units of every line's text, start
  // and end, with separators that cannot occur in the numbers.
  var hash = 0x811c9dc5;
  void add(String value) {
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
  }

  for (final line in lines) {
    add(line.text);
    add('\u0001${line.startTime.inMilliseconds}');
    add('\u0001${line.endTime.inMilliseconds}\u0002');
  }
  final digest = hash.toRadixString(16).padLeft(8, '0');
  return '${lines.length}:$digest';
}
