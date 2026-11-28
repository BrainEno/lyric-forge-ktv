import '../../../core/onboarding/getting_started_store.dart';
import '../../player/domain/repositories/play_history_repository.dart';
import '../../player/domain/services/audio_player_service.dart';
import '../../player/domain/services/playback_session_service.dart';
import '../../project/domain/models/lyric_review_overview.dart';
import '../../project/domain/repositories/project_repository.dart';
import '../../transcription/domain/services/batch_transcription_queue.dart';
import '../../transcription/domain/services/transcription_settings_store.dart';
import '../../transcription/presentation/transcription_screen_dependencies.dart';

/// Collaborators used by the dashboard's recent activity and playback actions.
class DashboardDependencies {
  final ProjectRepository projectRepository;
  final PlayHistoryRepository playHistoryRepository;
  final PlaybackSessionService playbackSession;
  final AudioPlayerService audioPlayer;
  final BatchTranscriptionQueue transcriptionQueue;
  final TranscriptionSettingsStore transcriptionSettingsStore;
  final TranscriptionConfigDialogDependencies configDialogDependencies;

  /// Fires when a project is deleted or restored (D-064), so 最近工程
  /// follows an undo made from a snackbar.
  final Stream<void>? projectChanges;

  /// Where the 开始使用 checklist (D-070) is remembered; null hides it.
  final GettingStartedStore? gettingStartedStore;

  /// The lyric editor's 建议复核 counts (D-069), which tell the checklist
  /// whether the user has confirmed a line yet.
  final ProjectLyricReviewCounter? reviewCounter;

  const DashboardDependencies({
    required this.projectRepository,
    required this.playHistoryRepository,
    required this.playbackSession,
    required this.audioPlayer,
    required this.transcriptionQueue,
    required this.transcriptionSettingsStore,
    required this.configDialogDependencies,
    this.projectChanges,
    this.gettingStartedStore,
    this.reviewCounter,
  });
}
