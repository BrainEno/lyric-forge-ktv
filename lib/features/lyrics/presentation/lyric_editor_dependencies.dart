import '../../player/domain/services/audio_player_service.dart';
import '../../player/domain/services/playback_session_service.dart';
import '../../project/domain/repositories/project_repository.dart';
import '../domain/proofreading/forced_alignment_proofread_service.dart';
import '../domain/proofreading/project_proofread_evidence.dart';
import '../domain/services/lyric_file_export_service.dart';
import '../domain/services/lyric_file_import_service.dart';

/// Everything `LyricEditorScreen` needs, decided outside of it.
///
/// The screen used to reach into `AppServices.instance` for five services and
/// build its own forced-alignment runner out of four more. Both meant the
/// editor could not be constructed without the whole app singleton — including
/// in a widget test — and the wiring could only be exercised by opening the
/// editor and choosing the aligner.
///
/// This object is the seam: `lib/app/lyric_editor_assembly.dart` builds it from
/// `AppServices`, and the editor only sees domain contracts.
class LyricEditorDependencies {
  final ProjectRepository projectRepository;
  final PlaybackSessionService playbackSession;
  final AudioPlayerService audioPlayer;
  final LyricFileExportService lyricFileExport;
  final LyricFileImportService lyricFileImport;

  /// Produces word-level timing evidence for the forced aligner.
  ///
  /// Not nullable: an unavailable runtime throws with a message the user can
  /// act on, which the proofread flow already reports. That keeps the "is the
  /// aligner installed" question where it can actually be answered (settings
  /// storage and runtime inspection), instead of in the editor widget.
  final ForcedAlignmentRunner forcedAlignmentRunner;

  /// Optional verified project evidence, absent on hosts without the adapter.
  final ProjectProofreadEvidenceLoader? projectProofreadEvidenceLoader;

  const LyricEditorDependencies({
    required this.projectRepository,
    required this.playbackSession,
    required this.audioPlayer,
    required this.lyricFileExport,
    required this.lyricFileImport,
    required this.forcedAlignmentRunner,
    this.projectProofreadEvidenceLoader,
  });
}
